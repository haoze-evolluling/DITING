import type {
  AuthStatusResponse,
  LoginRequest,
  LoginResponse,
  SetupAuthRequest,
  ChangePasswordRequest,
  WebStatusResponse,
  ConfigureWebRequest,
} from './types';
import type { HttpTransport } from './http';
import type { EventChannel } from './ws';

/** Web 远程管理会话与登录认证 */
export class WebAuthApi {
  constructor(
    private http: HttpTransport,
    private events: EventChannel
  ) {}

  public getAuthStatus(): Promise<AuthStatusResponse> {
    return this.http.request<AuthStatusResponse>('/api/v1/auth/status');
  }

  public async login(req: LoginRequest): Promise<LoginResponse> {
    const res = await this.http.request<LoginResponse>('/api/v1/auth/login', {
      method: 'POST',
      body: JSON.stringify(req),
    });
    if (res?.token) {
      this.http.setSession(res.token);
      try {
        localStorage.setItem('diting_session_user', res.username);
      } catch {}
      this.events.reconnect();
      this.http.notifyAuthRequired(false);
    }
    return res;
  }

  public async logout(): Promise<void> {
    try {
      await this.http.request<void>('/api/v1/auth/logout', { method: 'POST' });
    } catch {}
    this.http.clearSession();
    this.http.notifyAuthRequired(true);
  }

  public async setupAuth(req: SetupAuthRequest): Promise<void> {
    await this.http.request<void>('/api/v1/auth/setup', {
      method: 'POST',
      body: JSON.stringify(req),
    });
  }

  public async changePassword(req: ChangePasswordRequest): Promise<void> {
    await this.http.request<void>('/api/v1/auth/password', {
      method: 'POST',
      body: JSON.stringify(req),
    });
  }

  public getWebStatus(): Promise<WebStatusResponse> {
    return this.http.request<WebStatusResponse>('/api/v1/web/status');
  }

  public async configureWeb(req: ConfigureWebRequest): Promise<void> {
    await this.http.request<void>('/api/v1/web/configure', {
      method: 'POST',
      body: JSON.stringify(req),
    });
  }
}
