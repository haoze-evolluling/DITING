export type DnsProtocolType = 'PLAIN' | 'DOH' | 'DOT';

export interface DnsPresetItem {
  id: string;
  provider: string;
  protocol: DnsProtocolType;
  server: string;
  url?: string;
  isDomestic: boolean;
  description?: string;
}

export interface DnsProviderGroup {
  name: string;
  isDomestic: boolean;
  presets: Record<DnsProtocolType, DnsPresetItem>;
}

export const DNS_PRESET_PROVIDERS: DnsProviderGroup[] = [
  {
    name: '阿里云',
    isDomestic: true,
    presets: {
      PLAIN: {
        id: '阿里云 (DNS)',
        provider: '阿里云',
        protocol: 'PLAIN',
        server: '223.5.5.5:53',
        url: '',
        isDomestic: true,
        description: '阿里巴巴公共 DNS，国内低时延解析',
      },
      DOT: {
        id: '阿里云 (DoT)',
        provider: '阿里云',
        protocol: 'DOT',
        server: 'dns.alidns.com:853',
        url: '',
        isDomestic: true,
        description: '阿里巴巴公共 DNS，基于 TLS 的加密解析',
      },
      DOH: {
        id: '阿里云 (DoH)',
        provider: '阿里云',
        protocol: 'DOH',
        server: 'dns.alidns.com',
        url: 'https://dns.alidns.com/dns-query',
        isDomestic: true,
        description: '阿里巴巴公共 DNS，基于 HTTPS 的加密解析',
      },
    },
  },
  {
    name: '腾讯云',
    isDomestic: true,
    presets: {
      PLAIN: {
        id: '腾讯云 (DNS)',
        provider: '腾讯云',
        protocol: 'PLAIN',
        server: '119.29.29.29:53',
        url: '',
        isDomestic: true,
        description: '腾讯云 DNSPod 公共解析，节点覆盖广',
      },
      DOT: {
        id: '腾讯云 (DoT)',
        provider: '腾讯云',
        protocol: 'DOT',
        server: 'dot.pub:853',
        url: '',
        isDomestic: true,
        description: '腾讯云 DNSPod，基于 TLS 的加密解析',
      },
      DOH: {
        id: '腾讯云 (DoH)',
        provider: '腾讯云',
        protocol: 'DOH',
        server: 'doh.pub',
        url: 'https://doh.pub/dns-query',
        isDomestic: true,
        description: '腾讯云 DNSPod，基于 HTTPS 的加密解析',
      },
    },
  },
  {
    name: '360',
    isDomestic: true,
    presets: {
      PLAIN: {
        id: '360 (DNS)',
        provider: '360',
        protocol: 'PLAIN',
        server: '101.226.4.6:53',
        url: '',
        isDomestic: true,
        description: '360 安全 DNS，提供基础安全防护',
      },
      DOT: {
        id: '360 (DoT)',
        provider: '360',
        protocol: 'DOT',
        server: 'dot.360.cn:853',
        url: '',
        isDomestic: true,
        description: '360 安全 DNS，基于 TLS 的加密解析',
      },
      DOH: {
        id: '360 (DoH)',
        provider: '360',
        protocol: 'DOH',
        server: 'doh.360.cn',
        url: 'https://doh.360.cn/dns-query',
        isDomestic: true,
        description: '360 安全 DNS，基于 HTTPS 的加密解析',
      },
    },
  },
  {
    name: 'OneDNS',
    isDomestic: true,
    presets: {
      PLAIN: {
        id: 'OneDNS (DNS)',
        provider: 'OneDNS',
        protocol: 'PLAIN',
        server: '117.50.10.10:53',
        url: '',
        isDomestic: true,
        description: '北京联盛 OneDNS，拦截恶意网站',
      },
      DOT: {
        id: 'OneDNS (DoT)',
        provider: 'OneDNS',
        protocol: 'DOT',
        server: 'dot.onedns.net:853',
        url: '',
        isDomestic: true,
        description: 'OneDNS 安全解析，基于 TLS 的加密解析',
      },
      DOH: {
        id: 'OneDNS (DoH)',
        provider: 'OneDNS',
        protocol: 'DOH',
        server: 'doh.onedns.net',
        url: 'https://doh.onedns.net/dns-query',
        isDomestic: true,
        description: 'OneDNS 安全解析，基于 HTTPS 的加密解析',
      },
    },
  },
  {
    name: 'Google',
    isDomestic: false,
    presets: {
      PLAIN: {
        id: 'Google (DNS)',
        provider: 'Google',
        protocol: 'PLAIN',
        server: '8.8.8.8:53',
        url: '',
        isDomestic: false,
        description: 'Google 全球公共 DNS 解析服务',
      },
      DOT: {
        id: 'Google (DoT)',
        provider: 'Google',
        protocol: 'DOT',
        server: 'dns.google:853',
        url: '',
        isDomestic: false,
        description: 'Google 公共 DNS，基于 TLS 的加密解析',
      },
      DOH: {
        id: 'Google (DoH)',
        provider: 'Google',
        protocol: 'DOH',
        server: 'dns.google',
        url: 'https://dns.google/dns-query',
        isDomestic: false,
        description: 'Google 公共 DNS，基于 HTTPS 的加密解析',
      },
    },
  },
  {
    name: 'Cloudflare',
    isDomestic: false,
    presets: {
      PLAIN: {
        id: 'Cloudflare (DNS)',
        provider: 'Cloudflare',
        protocol: 'PLAIN',
        server: '1.1.1.1:53',
        url: '',
        isDomestic: false,
        description: '全球快速且隐私友好的 DNS 服务',
      },
      DOT: {
        id: 'Cloudflare (DoT)',
        provider: 'Cloudflare',
        protocol: 'DOT',
        server: '1dot1dot1dot1.cloudflare-dns.com:853',
        url: '',
        isDomestic: false,
        description: 'Cloudflare 1.1.1.1，基于 TLS 的加密解析',
      },
      DOH: {
        id: 'Cloudflare (DoH)',
        provider: 'Cloudflare',
        protocol: 'DOH',
        server: 'cloudflare-dns.com',
        url: 'https://cloudflare-dns.com/dns-query',
        isDomestic: false,
        description: 'Cloudflare 1.1.1.1，基于 HTTPS 的加密解析',
      },
    },
  },
];

export const BOOTSTRAP_PRESETS = [
  { name: '阿里云', ip: '223.5.5.5:53' },
  { name: '腾讯云', ip: '119.29.29.29:53' },
  { name: '360', ip: '101.226.4.6:53' },
  { name: 'OneDNS', ip: '117.50.10.10:53' },
  { name: 'Google', ip: '8.8.8.8:53' },
  { name: 'Cloudflare', ip: '1.1.1.1:53' },
];
