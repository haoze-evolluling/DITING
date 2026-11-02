package tunnel

import "testing"

func TestParseOutboundProxyConfig_Scope(t *testing.T) {
	cfg, err := parseOutboundProxyConfig(`{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":1080,"scope":"apps","uids":[10100,0,-1]}`)
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.perApp() {
		t.Fatal("expected per-app scope")
	}
	if !cfg.proxiesUID(10100) {
		t.Fatal("selected UID must be proxied")
	}
	for _, uid := range []int{10200, 0, UIDUnknown} {
		if cfg.proxiesUID(uid) {
			t.Fatalf("uid %d must stay direct", uid)
		}
	}

	legacy, err := parseOutboundProxyConfig(`{"enabled":true,"protocol":"http","host":"127.0.0.1","port":8080}`)
	if err != nil {
		t.Fatal(err)
	}
	if legacy.perApp() || !legacy.proxiesUID(UIDUnknown) {
		t.Fatal("config without scope must proxy every flow")
	}
}

func TestOutboundRoute_PerAppKeepsDNSDirect(t *testing.T) {
	cfg, _ := parseOutboundProxyConfig(`{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":1080,"scope":"apps","uids":[10100]}`)
	proxy := newFlowOutbound(cfg, nil, nil)
	defer proxy.Close()
	route := newOutboundRoute(cfg, proxy, nil)

	if _, ok := route.resolverOutbound().(*directFlowOutbound); !ok {
		t.Fatal("DNS upstream must be direct in per-app mode")
	}
	if route.forUID(10100) != proxy {
		t.Fatal("selected UID must use the proxy")
	}
	if _, ok := route.forUID(10200).(*directFlowOutbound); !ok {
		t.Fatal("unselected UID must be direct")
	}

	all, _ := parseOutboundProxyConfig(`{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":1080}`)
	allRoute := newOutboundRoute(all, proxy, nil)
	if allRoute.resolverOutbound() != proxy || allRoute.forUID(UIDUnknown) != proxy {
		t.Fatal("all scope must proxy DNS and every flow")
	}
}
