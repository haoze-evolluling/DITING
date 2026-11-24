export interface DiagnosticAnswer {
  name: string;
  recordType: string;
  ttl: number;
  value: string;
}

export interface DiagnosticQueryResult {
  domain: string;
  qtype: string;
  success: boolean;
  rcode: number;
  rcodeName: string;
  elapsedMs: number;
  /** `local` 表示经由本机 DNS 监听，`upstream` 表示直连上游。 */
  source: "local" | "upstream" | string;
  answers: DiagnosticAnswer[];
  message?: string;
}

export interface DiagnosticUpstreamResult {
  id: string;
  protocol: string;
  server: string;
  url?: string;
  success: boolean;
  latencyMs: number;
  attempts: number;
  successCount: number;
  message?: string;
}

export interface DiagnosticPingReply {
  sequence: number;
  elapsedMs?: number | null;
  ttl?: number | null;
  timeout: boolean;
}

export interface DiagnosticPingResult {
  target: string;
  resolvedAddress: string;
  addressFamily: string;
  transmitted: number;
  received: number;
  lossPercent: number;
  minMs?: number | null;
  avgMs?: number | null;
  maxMs?: number | null;
  jitterMs?: number | null;
  success: boolean;
  message?: string;
  replies: DiagnosticPingReply[];
}

export interface DiagnosticTraceHop {
  hop: number;
  address?: string | null;
  elapsedMs?: number | null;
  timeout: boolean;
}

export interface DiagnosticTraceResult {
  target: string;
  resolvedAddress: string;
  hops: DiagnosticTraceHop[];
  reached: boolean;
  message?: string;
}
