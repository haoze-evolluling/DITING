export type OpenWrtTakeoverMode = "replace_dnsmasq" | "dnsmasq_upstream";

export interface OpenWrtStatus {
  supported: boolean;
  distro: string;
  active: boolean;
  dnsRunning: boolean;
  mode: OpenWrtTakeoverMode | string;
  dnsmasqPort: number;
  upstreamPort: number;
  forwardLocalDomain: boolean;
  localDomain: string;
  forceRedirect53: boolean;
  redirectActive: boolean;
  desiredActive: boolean;
  firewallBackend: string;
  listenAddresses: string[];
  persistentDir: string;
  volatileDir: string;
}

export interface ConfigureOpenWrtPatch {
  mode?: OpenWrtTakeoverMode | string;
  dnsmasqPort?: number;
  upstreamPort?: number;
  forwardLocalDomain?: boolean;
  forceRedirect53?: boolean;
}
