# laravel-react-starter

Laravel + Inertia + React + TypeScript を Fly.io で動かすためのテンプレートリポジトリ。

## 実証記録

捨てアプリ `react-starter-probe` を Fly.io (nrt) に実際にデプロイして検証済み。
検証後、捨てアプリは即日破棄。

| 項目             | 値                                                                          |
| ---------------- | --------------------------------------------------------------------------- |
| 検証日           | 2026-08-01                                                                  |
| 結果             | `/up` → **200** ／ アセット26本すべて 200 ／ **ブラウザで画面の描画を確認** |
| Laravel          | 13.23.0                                                                     |
| PHP              | 8.4.24（本番イメージ内で確認）                                              |
| Node             | 24.18.1（ローカルと本番で一致）                                             |
| Vite             | 8.2.0（Rolldown）                                                           |
| Inertia          | 3.x ／ React 19 ／ TypeScript                                               |
| ビルド           | 2271 modules                                                                |
| 起動時キャッシュ | config / routes-v7 / packages / services すべて生成成功                     |
| npm 依存         | 48（追加判定の基準線）                                                      |

検証中に見つけて修正した不具合は「踏んだ罠」に記録。

## 使い方

```
gh repo create <app-name> --template kayame0120-code/laravel-react-starter --private --clone
cd <app-name>
composer install
cp .env.example .env && php artisan key:generate
npm ci && npm run build
sed -i "s/^app = 'CHANGEME-app-name'$/app = '<app-name>'/" fly.toml
```

## 触る前に読むこと

### 版の正本は `fly.toml` の `[build.args]`

`Dockerfile` の `ARG` 既定値は素の `docker build` 用の保険。
版を変えるときは**両方を同じ数字にする**。照合：

```
D=$(grep -oP '^ARG NODE_VERSION=\K\S+' Dockerfile); F=$(grep -oP "NODE_VERSION = '\K[^']*" fly.toml)
[ "$D" = "$F" ] && echo OK || echo MISMATCH
```

Node 24 は Active LTS（EOL 2028-04）。PHP 8.4 は `.fly/php/packages/` の天井。

### `.fly/` は改変しない

nginx / php-fpm / supervisor / entrypoint の一式。本番稼働実績のある構成。
`sites-enabled/default` はコンテナ内を指すシンボリックリンクなので、
母艦から `diff -r` すると「リンク先が無い」と言われる（正常）。
比較は `diff -r --no-dereference` を使う。

### `fly launch` を打たない

`fly launch` はソースをスキャンして `Dockerfile` / `fly.toml` を書き換えにくる。
新規アプリは `fly apps create` + `fly deploy -c <config>` で作る。
HTTP サービスが定義されていれば公開 IP は `fly deploy` が自動で確保する。

## 踏んだ罠（消さない）

### 1. Dockerfile の composer → npm の順序を入れ替えない

`@laravel/vite-plugin-wayfinder` が `npm run build` の途中で
`php artisan wayfinder:generate` を呼ぶ。`vendor/` が無いとビルドが必ず落ちる。
Blade 時代の Dockerfile は npm が先だったため、そのままでは通らない。

### 2. `trustProxies` が無いと画面が真っ黒になる

Fly Proxy が TLS を終端し、コンテナへは平文 HTTP:8080 で転送する。
`bootstrap/app.php` に `$middleware->trustProxies(at: '*')` が無いと
Laravel は自分が http で動いていると誤認し、アセットURLを `http://` で生成する。
HTTPS ページ上の http アセットはブラウザが**無警告で破棄**するため、
HTML の殻だけが残り背景色だけの真っ黒な画面になる。
`/up` は 200 を返し、アセットも直接叩けば 200 で、ログにも何も出ない。

### 3. 改行は LF 固定

`.gitattributes` で強制。Windows 側の VSCode（`\\wsl$\...`）で開くと CRLF になり、
`.dockerignore` のパターンが黙って効かなくなる。
WSL 内で開くときは VSCode の WSL Remote を使う。

### 4. `public/hot` を `.dockerignore` から外さない

`npm run dev` が残す印のファイル。イメージに紛れ込むと
Laravel がアセットを localhost:5173 から取ろうとして画面が出なくなる。

## 既知の宿題

- `fly deploy` は既定でマシンを2台作る。個人アプリでは `fly scale count 1` にする
- 本番イメージに実行時不要な Node 一式（約150MB）が残る。マルチステージ化の余地あり
- `wayfinder-*.js` が 315kB（全チャンク中最大）。ルート数が増えると効いてくる
- `laravel:fonts` が `fontaine` を求める警告。`optimizedFallbacks: false` で消す想定
- `SESSION_DRIVER = 'cookie'`（4KB上限）
- CSP ミドルウェアは未同梱。E2E暗号化を使う派生先で移植する
