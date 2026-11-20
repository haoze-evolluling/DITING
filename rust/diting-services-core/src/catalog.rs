use serde_json::Value;

pub struct Service {
    pub id: &'static str,
    pub name: &'static str,
    pub category: &'static str,
    pub domains: &'static [&'static str],
}

pub const CATALOG: &[Service] = &[
    Service {
        id: "facebook",
        name: "Facebook",
        category: "social",
        domains: &["facebook.com", "fbcdn.net", "fb.com", "messenger.com"],
    },
    Service {
        id: "instagram",
        name: "Instagram",
        category: "social",
        domains: &["instagram.com", "cdninstagram.com"],
    },
    Service {
        id: "twitter",
        name: "X (Twitter)",
        category: "social",
        domains: &["twitter.com", "x.com", "t.co", "twimg.com"],
    },
    Service {
        id: "reddit",
        name: "Reddit",
        category: "social",
        domains: &["reddit.com", "redd.it", "redditmedia.com"],
    },
    Service {
        id: "tiktok",
        name: "TikTok",
        category: "social",
        domains: &["tiktok.com", "tiktokcdn.com", "tiktokv.com"],
    },
    Service {
        id: "weibo",
        name: "微博",
        category: "social",
        domains: &["weibo.com", "weibo.cn", "sinaimg.cn"],
    },
    Service {
        id: "youtube",
        name: "YouTube",
        category: "video",
        domains: &["youtube.com", "youtu.be", "googlevideo.com", "ytimg.com"],
    },
    Service {
        id: "netflix",
        name: "Netflix",
        category: "video",
        domains: &["netflix.com", "nflxvideo.net", "nflximg.net"],
    },
    Service {
        id: "twitch",
        name: "Twitch",
        category: "video",
        domains: &["twitch.tv", "ttvnw.net", "jtvnw.net"],
    },
    Service {
        id: "bilibili",
        name: "哔哩哔哩",
        category: "video",
        domains: &["bilibili.com", "bilivideo.com", "hdslb.com"],
    },
    Service {
        id: "whatsapp",
        name: "WhatsApp",
        category: "messaging",
        domains: &["whatsapp.com", "whatsapp.net"],
    },
    Service {
        id: "telegram",
        name: "Telegram",
        category: "messaging",
        domains: &["telegram.org", "t.me", "telegram.me"],
    },
    Service {
        id: "discord",
        name: "Discord",
        category: "messaging",
        domains: &["discord.com", "discordapp.com", "discord.gg"],
    },
    Service {
        id: "steam",
        name: "Steam",
        category: "gaming",
        domains: &["steampowered.com", "steamcommunity.com", "steamstatic.com"],
    },
    Service {
        id: "epicgames",
        name: "Epic Games",
        category: "gaming",
        domains: &["epicgames.com", "epicgames.dev", "unrealengine.com"],
    },
    Service {
        id: "doubleclick",
        name: "DoubleClick",
        category: "ads",
        domains: &["doubleclick.net", "googleads.g.doubleclick.net"],
    },
    Service {
        id: "googlesyndication",
        name: "Google AdSense",
        category: "ads",
        domains: &["googlesyndication.com", "googleadservices.com"],
    },
];

pub const CATEGORIES: &[&str] = &["social", "video", "messaging", "gaming", "ads"];

fn service_json(service: &Service) -> Value {
    serde_json::json!({
        "id": service.id,
        "name": service.name,
        "category": service.category,
        "domains": service.domains,
    })
}

pub fn catalog_json() -> Value {
    let services: Vec<Value> = CATEGORIES
        .iter()
        .flat_map(|category| {
            CATALOG
                .iter()
                .filter(move |service| service.category == *category)
        })
        .map(service_json)
        .collect();
    serde_json::json!({
        "categories": CATEGORIES,
        "services": services,
    })
}

pub fn find(id: &str) -> Option<&'static Service> {
    CATALOG.iter().find(|service| service.id == id)
}
