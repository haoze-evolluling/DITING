# 云控贡献者名单

名单由仓库根目录的 `recognition_members.json` 驱动。修改成员或头像后，将该 JSON 与 `avatars/` 中对应的 JPG 文件一起推送到 GitHub `main` 分支即可生效，无需发布新版 APP。

JSON 必须包含 `version`、`sponsors` 和 `coBuilders`。每个数组项只包含非空的 `name` 与 `avatarFileName`；头像文件名必须匹配 `[a-z0-9_]+_avatar.jpg`。数组顺序即展示顺序：赞助者按赞助时间，共建者按约定的名称顺序。同一数组内成员名称和头像文件名不能重复。

APP 每次进入名单页都会从 GitHub 请求配置，成功后原子写入本地缓存。请求失败或配置无效时会继续显示上次成功缓存；首次安装且无法联网时名单为空。APP 不内置名单配置。
