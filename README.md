# github-deploy-key
githubのdeployキーを自動生成するためのbash script

## 概要

`setup-deploy-key.sh` は、GitHub リポジトリ専用のデプロイキーを作成し、その鍵を使ってリポジトリをクローンします。デプロイキーとは、1 つのリポジトリにだけ登録する SSH 鍵のことで、漏えいしても影響がそのリポジトリに限られます。

鍵の指定はクローンしたリポジトリの `.git/config`（`core.sshCommand`）にだけ保存されるため、`~/.ssh/config` や他のリポジトリには影響しません。

## 必要なもの

- `bash`、`git`、`ssh`、`ssh-keygen`
- プロキシを使う環境では `nc`（Ubuntu では `netcat-openbsd`）
- 対象リポジトリの管理者権限（デプロイキーの登録に必要）

## 使い方

1. クローン先にしたいディレクトリに移動して、スクリプトを実行します。

   ```bash
   cd /path/to/workspace
   bash /path/to/setup-deploy-key.sh
   ```

2. `GitHub repository SSH URL:` と表示されたら、SSH 形式の URL を入力します。`ssh://git@github.com/OWNER/REPO.git` の形式も使えますが、`https://` の URL は使えません。

   ```text
   git@github.com:OWNER/REPO.git
   ```

3. 表示された公開鍵をコピーし、`https://github.com/OWNER/REPO/settings/keys` の「Add deploy key」から登録します。`git push` が必要な場合だけ「Allow write access」にチェックを入れてください。秘密鍵は貼り付けないでください。

4. 登録が済んだらターミナルに戻って Enter を押すと、`./REPO` にクローンされます。中止するときは Ctrl-C を押します。

クローン後は、そのディレクトリ内で通常どおり `git pull` や `git push` を実行できます。

## 鍵とクローン先の扱い

- 秘密鍵は `~/.ssh/id_ed25519_deploy_OWNER_REPO`、公開鍵はその `.pub` として保存されます。
- 秘密鍵にはパスフレーズを設定しません。無人で使える代わりに、ファイルを読める人は誰でも鍵を使えます。
- 同じ名前の鍵がすでにあれば、新しく作らず再利用します。秘密鍵と公開鍵の片方だけがある場合は、何も上書きせずエラーで停止します。
- クローン先の `./REPO` がすでに存在する場合は、エラーで停止します。

## プロキシ環境での利用

プロキシは自動で検出します。環境変数を `https_proxy`、`HTTPS_PROXY`、`http_proxy`、`HTTP_PROXY`、`all_proxy`、`ALL_PROXY` の順に調べ、どれも未設定なら Git の `http.proxy`（global、system の順）を使います。

- プロキシがある場合は、`nc` 経由で `ssh.github.com` の 443 番ポートに接続します。
- プロキシがない場合は、`github.com` の 22 番ポートに直接接続します。
- 使える形式は `host:port`、`http://host:port`、`socks5://host:port`、`socks5h://host:port` です。
- `https://` のプロキシと、ユーザー名やパスワードを含むプロキシ URL には対応していません。

接続方法はクローン時に `core.sshCommand` へ固定されます。あとでプロキシの有無が変わったら、そのリポジトリの `core.sshCommand` を手動で変更してください。
