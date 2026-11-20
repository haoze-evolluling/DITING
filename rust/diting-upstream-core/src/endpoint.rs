use diting_go_compat::netaddr::{join_host_port_text, split_host_port};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TargetProtocol {
    Plain,
    Dot,
}

impl TargetProtocol {
    pub fn default_port(self) -> &'static str {
        match self {
            TargetProtocol::Plain => "53",
            TargetProtocol::Dot => "853",
        }
    }
}

pub fn split_target(server: &str, protocol: TargetProtocol) -> (String, String) {
    match split_host_port(server) {
        Ok((host, port)) => (host.to_string(), port.to_string()),
        Err(_) => (server.to_string(), protocol.default_port().to_string()),
    }
}

pub fn dial_address(host: &str, port: &str, bootstrapped: &str) -> String {
    let target = if bootstrapped.is_empty() {
        host
    } else {
        bootstrapped
    };
    join_host_port_text(target, port)
}

#[cfg(test)]
mod tests;
