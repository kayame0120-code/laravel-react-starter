# laravel-react-starter

Laravel + Inertia + React + TypeScript を Fly.io で動かすためのテンプレートリポジトリ。
DB は **SQLite**。アプリと同じマシン上の Fly Volume に置き、DBサーバーを別に立てない。

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

### 未検証（この構成では一度も本番に載っていない）

上の記録は PostgreSQL 構成・`ARG` 方式のときのもの。以下は**実デプロイでしか判明しない**。

| 未検証 | 失敗したときの見え方 |
| --- | --- |
| `ENV` 方式でビルドが通るか | `php -v` 照合（Dockerfile 内）でビルドが停止する |
| `[mounts]` を持つ構成で起動するか | ボリューム関連のエラーでデプロイが停止する |
| 起動時マイグレーションが `/data` へ書けるか | 起動はするがテーブルが無い、または権限エラーで起動を繰り返す |

## 使い方

```
gh repo create <app-name> --template kayame0120-code/laravel-react-starter --private --clone
cd <app-name>
composer install
cp .env.example .env && php artisan key:generate
touch database/database.sqlite && php artisan migrate
npm ci && npm run build
sed -i "s/^app = 'CHANGEME-app-name'$/app = '<app-name>'/" fly.toml
```

Fly 側は `fly launch` を使わずに作る（後述）。

```
fly apps create <app-name> --org personal
fly volumes create data --region nrt --size 1 --app <app-name>
fly secrets set APP_KEY="$(grep '^APP_KEY=' .env | cut -d= -f2-)" -a <app-name>
fly secrets list -a <app-name>
fly deploy -c fly.toml -a <app-name> --ha=false
```

ボリューム名 `data` は `fly.toml` の `[mounts] source` と一致していなければならない。
一致しないと「fly.toml がボリュームを要求しているがマシンに付いていない」で停止する。

## 触る前に読むこと

### 版の正本は `Dockerfile` の `ENV`

```
ENV PHP_VERSION=8.4 \
    NODE_VERSION=24
```

版はここでしか定義されていない。`fly.toml` は版を持たない。照合は不要。

`--build-arg` では変わらない。`ENV` は `--build-arg` で上書きできず、これは意図した設計である。
`ARG` は「外から渡せる」ための構文であり、**渡せることは、意図しない値が渡っても気づけないことでもある**。
実際、`fly.toml` と `Dockerfile` の両方に 8.4 と書いてあるのにビルドが 8.3 で走り、
出所を特定できないまま1日を溶かす事故が起きた（`--no-cache` でもキャッシュ説は否定された）。
版を外から差し替えられる仕組みそのものが入り口だったので、その仕組みを外した。

ビルドの中で `php -v` と `node -v` を実物と照合しているため、
**焼けた版が意図と違えばその場でビルドが止まる**。composer install まで進んでから露見しない。

PHP を変える場合は `.fly/php/packages/<版>.txt` の存在を先に確認する。
Node 24 は Active LTS（EOL 2028-04）。PHP 8.4 は `.fly/php/packages/` の天井。

なお `ADD` / `COPY` の**転送元パス**は `ENV` を展開しない（展開されるのは `RUN` の中と転送先だけ）。
そのためパッケージ一覧はディレクトリごとイメージへ入れ、`RUN` の中で選んでいる。
ここを `COPY .fly/php/packages/${PHP_VERSION}.txt` に戻すと**黙って壊れる**。

### DB は SQLite。ファイル1個であり、置き場所がすべて

```
/data/database.sqlite       ボリューム上   → 再デプロイしても残る    ✓
database/database.sqlite    コンテナの中   → 再デプロイで丸ごと消える ✗
```

本番の `DB_DATABASE` は**絶対パス**で指定する（`fly.toml` の `[env]`）。
相対パスにするとイメージの中を指す。**動く。しばらく動く。次のデプロイまでは。**
「登録したデータがデプロイのたびに消える」が出たら、まずここを疑う。

`config/database.php` の sqlite 節は WAL / NORMAL / busy_timeout 5000 / IMMEDIATE を設定済み。
素の設定は複数プロセスからの書き込みを想定しておらず、そのままでは `SQLITE_BUSY` で落ちる。
効いていることは設定ファイルではなく DB が返す値で確かめる。

```
fly ssh console -a <app-name> -C "php /var/www/html/artisan tinker --execute=\"echo DB::select('PRAGMA journal_mode')[0]->journal_mode;\""
```

セッション・キャッシュ・キューは DB に置かない（`cookie` / `file` / `sync`）。
SQLite への書き込みを増やさないため。キューを `database` にすると、
ゼロスケール中はワーカーが居らずジョブが**永久に滞留する**（エラーも出ない）。

### `release_command` を足さない

`release_command` は**使い捨ての一時マシン**で走る。
Fly の公式ドキュメントは、ボリュームが使えない場面として「ビルド時」と
「`release_command` の一時マシン」の2つを明記している。
SQLite の実体はボリューム上にあるため、そこからは到達できない。

```
release_command   一時マシン  ボリューム無し → /data が無い → 空振りか停止
起動時スクリプト   本番マシン  ボリューム有り → /data に書ける  ✓
```

マイグレーションは `.fly/scripts/00-database.sh` が起動のたびに走らせる。
「デプロイしたのにテーブルが無い」を防ぐ役割は、そちらが引き継いでいる。

### マシンは1台。2台になると DB が2つに割れる

ボリュームは**マシンごとに独立して存在する**。2台になればボリュームも2つ作られ、
SQLite のファイルが割れて別々のデータになる。

```
マシンA ── ボリュームA ── database.sqlite   ここに登録したデータが
マシンB ── ボリュームB ── database.sqlite   こちらには存在しない
```

エラーは出ない。リクエストがどちらに振られたかで見えたり見えなかったりするため、
**「たまに消える」という形で現れ、原因に辿り着きにくい**。
`fly deploy` には `--ha=false` を付ける。既に増えていたら `fly scale count 1` で戻す。

### `.fly/` は改変しない

nginx / php-fpm / supervisor / entrypoint の一式。本番稼働実績のある構成。
`sites-enabled/default` はコンテナ内を指すシンボリックリンクなので、
母艦から `diff -r` すると「リンク先が無い」と言われる（正常）。
比較は `diff -r --no-dereference` を使う。

例外は `.fly/scripts/` で、ここはアプリ固有の起動処理を置く場所。
アルファベット順に実行され、1本でも失敗すれば `entrypoint` が起動を止める。

### `fly launch` を打たない

`fly launch` はソースをスキャンして `Dockerfile` / `fly.toml` を書き換えにくる。
新規アプリは `fly apps create` + `fly deploy -c <config>` で作る。
HTTP サービスが定義されていれば公開 IP は `fly deploy` が自動で確保する。

書き換え以外にも実害がある。flyctl は Laravel を検出すると
**Managed Postgres と Redis の作成を提案してくる**。対話で1つでも Yes にすると
月額数十ドルの課金が始まる。SQLite 構成ではどちらも要らない。
提案画面で「設定を調整するか」に Yes を選ぶとブラウザ連携に入り、
WSL のようにブラウザを開けない環境では `Error: not found` で中断する。

やむを得ず打つ場合は `--no-deploy --copy-config --no-db --no-redis --no-object-storage --yes` を必ず付ける。

### スケジューラはコンテナの外から起こす

このテンプレートは cron を**入れていない**。

`auto_stop_machines` を使う構成では、アクセスが無い間マシンが眠る。
眠っている間はコンテナ内の cron も眠るため、「毎日9時に通知」は
**その時刻に誰も起きていない**という理由で実行されない。
設定の問題ではなく構造の問題であり、cron を足しても直らない。

定時実行が要るアプリは、外部から HTTP でマシンを起こす。

1. `schedule:run` を叩くルートを用意し、推測できないトークンで保護する
2. 外部のスケジューラ（cron-job.org など）から定時にその URL を叩く
3. マシンが起き、Laravel のスケジューラが走る

常時起動（`min_machines_running = 1`）にすれば cron も使えるが、そのぶん課金が増える。

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

### 5. `/data` の所有者が root だと、参照は動くのに登録だけ 500 になる

ボリュームは root 所有でマウントされる。`www-data` が書けないと登録系が全滅するが、
**読み取りは通るため画面は出る**。起動スクリプトが `chown` しているので通常は起きないが、
症状を知らないと「なぜか保存だけ失敗する」で止まる。

```
fly ssh console -a <app-name> -C "sh -c 'ls -l /data/'"
```

### 6. `mem_overcommit_exceeded` はリポジトリと無関係

Fly ホスト側の混雑。ビルドは成功しているのにマシンの更新段階で出る。
`auto_stop_machines = 'suspend'` は復帰時にメモリ像を丸ごと確保し直すため
この門に引っかかりやすい。このテンプレートは `'stop'` を既定にしている。
詰まったら `fly machine stop` → `fly machine start` でメモリを解放してから起こす
（ボリュームはマシンと独立なのでデータは失われない）。時間をおくのも有効。

## 既知の宿題

- 本番イメージに実行時不要な Node 一式（約150MB）が残る。マルチステージ化の余地あり
- `wayfinder-*.js` が 315kB（全チャンク中最大）。ルート数が増えると効いてくる
- `laravel:fonts` が `fontaine` を求める警告。`optimizedFallbacks: false` で消す想定
- `SESSION_DRIVER = 'cookie'`（4KB上限）
- CSP ミドルウェアは未同梱。E2E暗号化を使う派生先で移植する
- ボリュームのスナップショット保持日数は既定のまま。延長するなら `fly volumes update`
- SQLite で足りなくなったときの昇格経路。エンジン依存の SQL（`whereRaw` 等）を書かなければ
  取り出しと投入だけで済む。手順は必要になった日に書く