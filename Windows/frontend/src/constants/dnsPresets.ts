export type DnsProtocolType = 'PLAIN' | 'DOH' | 'DOT';

export interface DnsPresetItem {
  id: string;
  protocol: DnsProtocolType;
  server: string;
  url?: string;
  description?: string;
}

export interface DnsProviderGroup {
  name: string;
  presets: Record<DnsProtocolType, DnsPresetItem>;
}

export const DNS_PRESET_PROVIDERS: readonly DnsProviderGroup[] = [
  {
    name: '阿里云',
    presets: {
      PLAIN: {
        id: '阿里云 (DNS)',
        protocol: 'PLAIN',
        server: '223.5.5.5:53',
        url: '',
        description: '阿里巴巴公共 DNS，国内低时延解析',
      },
      DOT: {
        id: '阿里云 (DoT)',
        protocol: 'DOT',
        server: 'dns.alidns.com:853',
        url: '',
        description: '阿里巴巴公共 DNS，基于 TLS 的加密解析',
      },
      DOH: {
        id: '阿里云 (DoH)',
        protocol: 'DOH',
        server: 'dns.alidns.com',
        url: 'https://dns.alidns.com/dns-query',
        description: '阿里巴巴公共 DNS，基于 HTTPS 的加密解析',
      },
    },
  },
  {
    name: '腾讯云',
    presets: {
      PLAIN: {
        id: '腾讯云 (DNS)',
        protocol: 'PLAIN',
        server: '119.29.29.29:53',
        url: '',
        description: '腾讯云 DNSPod 公共解析，节点覆盖广',
      },
      DOT: {
        id: '腾讯云 (DoT)',
        protocol: 'DOT',
        server: 'dot.pub:853',
        url: '',
        description: '腾讯云 DNSPod，基于 TLS 的加密解析',
      },
      DOH: {
        id: '腾讯云 (DoH)',
        protocol: 'DOH',
        server: 'doh.pub',
        url: 'https://doh.pub/dns-query',
        description: '腾讯云 DNSPod，基于 HTTPS 的加密解析',
      },
    },
  },
  {
    name: '360',
    presets: {
      PLAIN: {
        id: '360 (DNS)',
        protocol: 'PLAIN',
        server: '101.226.4.6:53',
        url: '',
        description: '360 安全 DNS，提供基础安全防护',
      },
      DOT: {
        id: '360 (DoT)',
        protocol: 'DOT',
        server: 'dot.360.cn:853',
        url: '',
        description: '360 安全 DNS，基于 TLS 的加密解析',
      },
      DOH: {
        id: '360 (DoH)',
        protocol: 'DOH',
        server: 'doh.360.cn',
        url: 'https://doh.360.cn/dns-query',
        description: '360 安全 DNS，基于 HTTPS 的加密解析',
      },
    },
  },
  {
    name: 'OneDNS',
    presets: {
      PLAIN: {
        id: 'OneDNS (DNS)',
        protocol: 'PLAIN',
        server: '117.50.10.10:53',
        url: '',
        description: '北京联盛 OneDNS，拦截恶意网站',
      },
      DOT: {
        id: 'OneDNS (DoT)',
        protocol: 'DOT',
        server: 'dot.onedns.net:853',
        url: '',
        description: 'OneDNS 安全解析，基于 TLS 的加密解析',
      },
      DOH: {
        id: 'OneDNS (DoH)',
        protocol: 'DOH',
        server: 'doh.onedns.net',
        url: 'https://doh.onedns.net/dns-query',
        description: 'OneDNS 安全解析，基于 HTTPS 的加密解析',
      },
    },
  },
  {
    name: 'Google',
    presets: {
      PLAIN: {
        id: 'Google (DNS)',
        protocol: 'PLAIN',
        server: '8.8.8.8:53',
        url: '',
        description: 'Google 全球公共 DNS 解析服务',
      },
      DOT: {
        id: 'Google (DoT)',
        protocol: 'DOT',
        server: 'dns.google:853',
        url: '',
        description: 'Google 公共 DNS，基于 TLS 的加密解析',
      },
      DOH: {
        id: 'Google (DoH)',
        protocol: 'DOH',
        server: 'dns.google',
        url: 'https://dns.google/dns-query',
        description: 'Google 公共 DNS，基于 HTTPS 的加密解析',
      },
    },
  },
  {
    name: 'Cloudflare',
    presets: {
      PLAIN: {
        id: 'Cloudflare (DNS)',
        protocol: 'PLAIN',
        server: '1.1.1.1:53',
        url: '',
        description: '全球快速且隐私友好的 DNS 服务',
      },
      DOT: {
        id: 'Cloudflare (DoT)',
        protocol: 'DOT',
        server: '1dot1dot1dot1.cloudflare-dns.com:853',
        url: '',
        description: 'Cloudflare 1.1.1.1，基于 TLS 的加密解析',
      },
      DOH: {
        id: 'Cloudflare (DoH)',
        protocol: 'DOH',
        server: 'cloudflare-dns.com',
        url: 'https://cloudflare-dns.com/dns-query',
        description: 'Cloudflare 1.1.1.1，基于 HTTPS 的加密解析',
      },
    },
  },
] as const;

export interface BootstrapPresetItem {
  name: string;
  ip: string;
}

export const BOOTSTRAP_PRESETS: readonly BootstrapPresetItem[] = [
  { name: '阿里云', ip: '223.5.5.5:53' },
  { name: '腾讯云', ip: '119.29.29.29:53' },
  { name: '360', ip: '101.226.4.6:53' },
  { name: 'OneDNS', ip: '117.50.10.10:53' },
  { name: 'Google', ip: '8.8.8.8:53' },
  { name: 'Cloudflare', ip: '1.1.1.1:53' },
] as const;
