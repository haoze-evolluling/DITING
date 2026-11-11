# 云控贡献者名单维护

名单由 GitHub 仓库远程驱动：根目录 `recognition_members.json`（数据）与 `avatars/`（头像）。修改后推送
到 `main` 分支即对所有客户端生效，无需发版。客户端进入名单页时拉取最新配置，校验通过后原子写入本地
缓存；网络异常或校验失败时降级展示上一次成功的缓存。

## 配置格式

根字段：`version`（整数，建议递增）、`sponsors`（赞助者）、`coBuilders`（共建者）。

成员项：

| 字段 | 类型 | 必填 | 说明 |
| :--- | :--- | :--- | :--- |
| `name` | String | 是 | 昵称，不可为空，同一数组内不得重复 |
| `avatarFileName` | String | 否 | 头像文件名；缺省或为空时使用内置 `default_avatar.png` |
| `count` | Integer | 否 | 仅对 `sponsors` 生效：同一人多次赞助时填累计次数（1–9999），缺省为 1；大于 1 时界面在昵称后显示 `×N` 角标。`coBuilders` 中的该字段会被忽略 |

约束：展示顺序与数组顺序一致；同一数组内 `name` 与非空 `avatarFileName` 不得重复。

## 头像规范

- 文件名匹配 `^[a-z0-9_]+_avatar\.jpg$`，例如 `alone_avatar.jpg`。
- 统一 JPG（内置缺省头像为 PNG），推荐 256×256 或 512×512 正方形，单张压缩到 100KB 以内。
