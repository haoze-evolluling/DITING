package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"sync"
	"time"
)

const (
	MaxFailedAttempts = 5
	LockoutDuration   = 5 * time.Minute
	DefaultSessionTTL = 7 * 24 * time.Hour

	// maxTrackedClients 防爆破表的条目上限，防止大量不同来源把内存撑爆
	maxTrackedClients = 4096
	// attemptEntryTTL 无锁定的失败计数在最后一次失败后保留的时长
	attemptEntryTTL = LockoutDuration
)

var (
	ErrNotInitialized     = errors.New("管理员账号尚未初始化")
	ErrAlreadyInitialized  = errors.New("管理员账号已初始化，请使用修改密码功能")
	ErrLockedOut          = errors.New("密码错误次数过多，账号已临时锁定")
	ErrInvalidCredentials = errors.New("用户名或密码错误")
	ErrSessionExpired     = errors.New("会话已过期，请重新登录")
	ErrInvalidSession     = errors.New("无效的会话凭证")
)

// Session 表示一次有效的登录会话
type Session struct {
	Token     string    `json:"token"`
	Username  string    `json:"username"`
	ClientIP  string    `json:"clientIP"`
	CreatedAt time.Time `json:"createdAt"`
	ExpiresAt time.Time `json:"expiresAt"`
}

// Status 描述认证系统的当前状态
type Status struct {
	Initialized     bool      `json:"initialized"`
	WebEnabled      bool      `json:"webEnabled"`
	Username        string    `json:"username"`
	Locked          bool      `json:"locked"`
	LockoutRemainingSec int64 `json:"lockoutRemainingSec"`
}

// Manager 统一处理 Web 管理凭据存储、防爆破频控与会话管理
type Manager struct {
	mu             sync.RWMutex
	username       string
	passwordHash   string
	salt           string
	sessionTimeout time.Duration

	// 防爆破频控 (按客户端 IP 跟踪)
	//
	// 两张表都必须有界：键来自网络对端地址，长时间运行的失败登录洪水
	// 若只增不减，会把与 DNS 核心同进程的服务内存拖垮。
	ipAttempts    map[string]int
	ipAttemptAt   map[string]time.Time // 最后一次失败时间，用于过期回收
	ipLockedUntil map[string]time.Time

	// 活跃会话
	sessions map[string]*Session
}

// NewManager 创建认证管理器
func NewManager(username, passwordHash, salt string, sessionTimeout time.Duration) *Manager {
	if sessionTimeout <= 0 {
		sessionTimeout = DefaultSessionTTL
	}
	if username == "" {
		username = "admin"
	}
	return &Manager{
		username:       username,
		passwordHash:   passwordHash,
		salt:           salt,
		sessionTimeout: sessionTimeout,
		ipAttempts:     make(map[string]int),
		ipAttemptAt:    make(map[string]time.Time),
		ipLockedUntil:  make(map[string]time.Time),
		sessions:       make(map[string]*Session),
	}
}

// HashPassword 对明文密码加盐并返回 SHA-256 哈希与盐值
func HashPassword(plainPassword, salt string) (hash string, usedSalt string) {
	if salt == "" {
		b := make([]byte, 16)
		_, _ = rand.Read(b)
		salt = hex.EncodeToString(b)
	}
	h := sha256.New()
	h.Write([]byte(salt))
	h.Write([]byte(plainPassword))
	return hex.EncodeToString(h.Sum(nil)), salt
}

// IsInitialized 检查是否已配置管理员密码
func (m *Manager) IsInitialized() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.passwordHash != ""
}

// GetUsername 获取当前管理员账号名称
func (m *Manager) GetUsername() string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.username
}

// GetCredentials 获取当前存储的哈希与盐值（供持久化使用）
func (m *Manager) GetCredentials() (username, passwordHash, salt string) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.username, m.passwordHash, m.salt
}

// SetupInitialCredentials 初始化管理员账号与密码（仅当未初始化时生效）
func (m *Manager) SetupInitialCredentials(username, plainPassword string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.passwordHash != "" {
		return ErrAlreadyInitialized
	}
	if len(plainPassword) < 4 {
		return errors.New("密码长度不能少于 4 位字符")
	}
	if username == "" {
		username = "admin"
	}

	hash, salt := HashPassword(plainPassword, "")
	m.username = username
	m.passwordHash = hash
	m.salt = salt
	return nil
}

// UpdateCredentials 修改管理员账号或密码（需提供原密码验证或直接由本地受信任提权调用）
func (m *Manager) UpdateCredentials(username, oldPassword, newPassword string, bypassOldAuth bool) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if len(newPassword) < 4 {
		return errors.New("新密码长度不能少于 4 位字符")
	}

	if !bypassOldAuth && m.passwordHash != "" {
		oldHash, _ := HashPassword(oldPassword, m.salt)
		if subtle.ConstantTimeCompare([]byte(oldHash), []byte(m.passwordHash)) != 1 {
			return errors.New("原密码不正确")
		}
	}

	if username == "" {
		username = m.username
		if username == "" {
			username = "admin"
		}
	}

	hash, salt := HashPassword(newPassword, "")
	m.username = username
	m.passwordHash = hash
	m.salt = salt

	// 密码变更后作废所有已有会话，要求重新登录
	m.sessions = make(map[string]*Session)
	return nil
}

// pruneLocked 回收过期的锁定与失败计数，并在超限时淘汰最旧条目。
//
// 调用方须持有写锁。没有这一步，失败的 IP 键会永久驻留。
func (m *Manager) pruneLocked(now time.Time) {
	for ip, until := range m.ipLockedUntil {
		if !now.Before(until) {
			delete(m.ipLockedUntil, ip)
			delete(m.ipAttempts, ip)
			delete(m.ipAttemptAt, ip)
		}
	}
	for ip, at := range m.ipAttemptAt {
		if now.Sub(at) > attemptEntryTTL {
			delete(m.ipAttemptAt, ip)
			delete(m.ipAttempts, ip)
		}
	}
	// 仍在窗口内但条目过多时，按最后失败时间淘汰最旧的一批
	if len(m.ipAttempts) <= maxTrackedClients {
		return
	}
	excess := len(m.ipAttempts) - maxTrackedClients
	for ip := range m.ipAttempts {
		if excess <= 0 {
			break
		}
		if _, locked := m.ipLockedUntil[ip]; locked {
			continue // 保留仍处于锁定中的条目
		}
		delete(m.ipAttempts, ip)
		delete(m.ipAttemptAt, ip)
		excess--
	}
}

// recordFailureLocked 记录一次失败尝试并在达到阈值时施加锁定。
//
// 调用方须持有写锁。返回错误供上层直接透出。
func (m *Manager) recordFailureLocked(clientIP string, now time.Time) error {
	m.ipAttempts[clientIP]++
	m.ipAttemptAt[clientIP] = now
	if m.ipAttempts[clientIP] >= MaxFailedAttempts {
		m.ipLockedUntil[clientIP] = now.Add(LockoutDuration)
		m.ipAttempts[clientIP] = 0
		return fmt.Errorf("密码连续错误 %d 次，已临时锁定 5 分钟", MaxFailedAttempts)
	}
	remainingAttempts := MaxFailedAttempts - m.ipAttempts[clientIP]
	return fmt.Errorf("%w (剩余重试次数: %d)", ErrInvalidCredentials, remainingAttempts)
}

// Login 校验管理员用户名和密码并颁发会话 Token
func (m *Manager) Login(username, plainPassword, clientIP string) (*Session, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	now := time.Now()
	m.pruneLocked(now)
	// 1. 检查客户端 IP 是否处于防爆破锁定保护中
	if until, ok := m.ipLockedUntil[clientIP]; ok && now.Before(until) {
		remaining := int64(until.Sub(now).Seconds())
		return nil, fmt.Errorf("%w，请在 %d 秒后重试", ErrLockedOut, remaining)
	}

	// 2. 检查是否已完成初始化
	if m.passwordHash == "" {
		return nil, ErrNotInitialized
	}

	// 3. 校验账号与密码哈希 (常量时间比较防侧信道攻击)
	calcHash, _ := HashPassword(plainPassword, m.salt)
	userMatch := (subtle.ConstantTimeCompare([]byte(username), []byte(m.username)) == 1)
	passMatch := (subtle.ConstantTimeCompare([]byte(calcHash), []byte(m.passwordHash)) == 1)

	if !userMatch || !passMatch {
		return nil, m.recordFailureLocked(clientIP, now)
	}

	// 4. 登录成功，清理失败频控计数
	delete(m.ipAttempts, clientIP)
	delete(m.ipAttemptAt, clientIP)
	delete(m.ipLockedUntil, clientIP)

	// 5. 颁发高熵安全会话 Token
	tokenBytes := make([]byte, 32)
	_, _ = rand.Read(tokenBytes)
	token := hex.EncodeToString(tokenBytes)

	sess := &Session{
		Token:     token,
		Username:  m.username,
		ClientIP:  clientIP,
		CreatedAt: now,
		ExpiresAt: now.Add(m.sessionTimeout),
	}
	m.sessions[token] = sess
	return sess, nil
}

// ValidateSession 检验会话 Token 是否有效
func (m *Manager) ValidateSession(token string) (*Session, bool) {
	if token == "" {
		return nil, false
	}
	m.mu.RLock()
	sess, ok := m.sessions[token]
	m.mu.RUnlock()

	if !ok {
		return nil, false
	}

	// 校验会话过期时间
	if time.Now().After(sess.ExpiresAt) {
		m.mu.Lock()
		delete(m.sessions, token)
		m.mu.Unlock()
		return nil, false
	}

	return sess, true
}

// RevokeSession 注销指定的会话 Token
func (m *Manager) RevokeSession(token string) {
	if token == "" {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.sessions, token)
}

// CheckIPLockout 检查指定 IP 是否正处于锁定保护状态
func (m *Manager) CheckIPLockout(clientIP string) (bool, int64) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	if until, ok := m.ipLockedUntil[clientIP]; ok {
		now := time.Now()
		if now.Before(until) {
			return true, int64(until.Sub(now).Seconds())
		}
	}
	return false, 0
}

// VerifyPassword 常量时间安全校验明文密码是否与管理员密码相匹配
func (m *Manager) VerifyPassword(plainPassword string) bool {
	m.mu.RLock()
	defer m.mu.RUnlock()

	if m.passwordHash == "" {
		return false
	}
	calcHash, _ := HashPassword(plainPassword, m.salt)
	return subtle.ConstantTimeCompare([]byte(calcHash), []byte(m.passwordHash)) == 1
}

// VerifyPasswordWithIP 校验管理员明文密码并实施客户端 IP 频控与防爆破锁定
func (m *Manager) VerifyPasswordWithIP(clientIP, plainPassword string) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	now := time.Now()
	m.pruneLocked(now)
	// 1. 检查客户端 IP 是否已被锁定
	if until, ok := m.ipLockedUntil[clientIP]; ok && now.Before(until) {
		remaining := int64(until.Sub(now).Seconds())
		return false, fmt.Errorf("%w，请在 %d 秒后重试", ErrLockedOut, remaining)
	}

	// 2. 检查系统是否已初始化
	if m.passwordHash == "" {
		return false, ErrNotInitialized
	}

	calcHash, _ := HashPassword(plainPassword, m.salt)
	passMatch := (subtle.ConstantTimeCompare([]byte(calcHash), []byte(m.passwordHash)) == 1)

	if !passMatch {
		return false, m.recordFailureLocked(clientIP, now)
	}

	// 密码匹配，清理频控计数
	delete(m.ipAttempts, clientIP)
	delete(m.ipAttemptAt, clientIP)
	delete(m.ipLockedUntil, clientIP)
	return true, nil
}


