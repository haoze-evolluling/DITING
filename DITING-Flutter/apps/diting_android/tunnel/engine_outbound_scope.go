// engine_outbound_scope.go picks the outbound transport per flow when the outbound proxy is scoped.
//
// Scope:
// - "all": every app flow and the engine's own DNS upstream dials use the proxy (original behaviour).
// - "apps": only flows owned by the selected UIDs use the proxy; everything else, including DNS
//   upstream dials and flows whose owner cannot be resolved, is dialed directly.

package tunnel

// outboundRoute is the per-session routing snapshot published by StartFull and cleared by Stop.
type outboundRoute struct {
	cfg    outboundProxyConfig
	proxy  flowOutbound
	direct flowOutbound
}

func newOutboundRoute(cfg outboundProxyConfig, proxy flowOutbound, protectFn func(fd int) bool) *outboundRoute {
	return &outboundRoute{cfg: cfg, proxy: proxy, direct: &directFlowOutbound{protectFn: protectFn}}
}

// resolverOutbound is the transport for the engine's own DNS upstream queries.
func (r *outboundRoute) resolverOutbound() flowOutbound {
	if r.cfg.perApp() {
		return r.direct
	}
	return r.proxy
}

func (r *outboundRoute) forUID(uid int) flowOutbound {
	if r.cfg.proxiesUID(uid) {
		return r.proxy
	}
	return r.direct
}

// outboundForUID returns the transport for a flow owned by uid. A nil route (engine stopped or not
// started through StartFull) falls back to a direct dialer, as the handlers did before.
func (e *Engine) outboundForUID(uid int, protectFn func(fd int) bool) flowOutbound {
	if e != nil {
		if route := e.outboundRouteView.Load(); route != nil {
			return route.forUID(uid)
		}
	}
	return &directFlowOutbound{protectFn: protectFn}
}

// outboundForFlow resolves the owner only when the scope needs it, so the "all" mode keeps its
// lookup-free path. The UID cache makes the repeat lookup cheap for flows already resolved.
func (e *Engine) outboundForFlow(flow flowID, protocol int, protectFn func(fd int) bool) flowOutbound {
	if e == nil {
		return &directFlowOutbound{protectFn: protectFn}
	}
	route := e.outboundRouteView.Load()
	if route == nil {
		return &directFlowOutbound{protectFn: protectFn}
	}
	if !route.cfg.perApp() {
		return route.proxy
	}
	return route.forUID(resolveFlowUID(e.uidResolver, protocol, flow))
}
