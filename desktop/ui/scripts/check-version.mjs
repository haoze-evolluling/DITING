import { readFileSync } from "node:fs";

function read(path) {
  return readFileSync(new URL(path, import.meta.url), "utf8");
}

function versionFileVersion() {
  const line = read("../../service/VERSION")
    .split(/\r?\n/)
    .map((value) => value.trim())
    .find((value) => value && !value.startsWith("#"));
  return (line ?? "").replace(/^v/, "");
}

const expected = versionFileVersion();
const packageJson = JSON.parse(read("../package.json"));
const cargo = read("../src-tauri/Cargo.toml");
const cargoVersion = cargo.match(/^version\s*=\s*"([^"]+)"/m)?.[1] ?? "";

const mismatches = [];
if (packageJson.version !== expected) {
  mismatches.push(`desktop/ui/package.json: ${packageJson.version} ≠ ${expected}`);
}
if (cargoVersion !== expected) {
  mismatches.push(`desktop/ui/src-tauri/Cargo.toml: ${cargoVersion} ≠ ${expected}`);
}

if (mismatches.length > 0) {
  console.error(`[版本检查] desktop/service/VERSION 为 ${expected}，但以下位置不一致：`);
  for (const mismatch of mismatches) console.error(`  - ${mismatch}`);
  console.error("请同步这些版本号后再构建。");
  process.exit(1);
}
