package ipc

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

// wsClient 表示一个活跃的 WebSocket 订阅客户端
type wsClient struct {
	conn *websocket.Conn
	send chan Event
}

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		// 允许本地进程、GUI 客户端及常规来源连接
		return true
	},
}

// Broadcast 推送事件到所有已连接的 WebSocket 订阅端
func (s *Server) Broadcast(evt Event) {
	if evt.Timestamp == 0 {
		evt.Timestamp = time.Now().UnixMilli()
	}
	select {
	case s.broadcast <- evt:
	default:
		// 缓冲区满时丢弃，防止反压阻塞核心 DNS 链路
	}
}

// runHub 集中调度 WebSocket 连接注册、解绑与事件广播
func (s *Server) runHub() {
	for {
		select {
		case <-s.stopCh:
			s.mu.Lock()
			for client := range s.clients {
				close(client.send)
				_ = client.conn.Close()
				delete(s.clients, client)
			}
			s.mu.Unlock()
			return
		case client := <-s.register:
			s.mu.Lock()
			s.clients[client] = true
			s.mu.Unlock()
		case client := <-s.unregister:
			s.mu.Lock()
			if _, ok := s.clients[client]; ok {
				delete(s.clients, client)
				close(client.send)
				_ = client.conn.Close()
			}
			s.mu.Unlock()
		case evt := <-s.broadcast:
			s.mu.RLock()
			for client := range s.clients {
				select {
				case client.send <- evt:
				default:
					// 客户端发送过慢，关闭并注销
					go func(c *wsClient) {
						select {
						case s.unregister <- c:
						case <-s.stopCh:
						}
					}(client)
				}
			}
			s.mu.RUnlock()
		}
	}
}

func (s *Server) handleEvents(w http.ResponseWriter, r *http.Request) {
	if !s.verifyToken(r) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}

	client := &wsClient{
		conn: conn,
		send: make(chan Event, 64),
	}

	select {
	case s.register <- client:
	case <-s.stopCh:
		_ = conn.Close()
		return
	}

	go s.writePump(client)
	go s.readPump(client)
}

func (s *Server) readPump(c *wsClient) {
	defer func() {
		select {
		case s.unregister <- c:
		case <-s.stopCh:
		}
	}()
	c.conn.SetReadLimit(512)
	_ = c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		_ = c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})
	for {
		if _, _, err := c.conn.ReadMessage(); err != nil {
			break
		}
	}
}

func (s *Server) writePump(c *wsClient) {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		_ = c.conn.Close()
	}()

	for {
		select {
		case evt, ok := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
			if !ok {
				_ = c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			data, err := json.Marshal(evt)
			if err != nil {
				continue
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, data); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
