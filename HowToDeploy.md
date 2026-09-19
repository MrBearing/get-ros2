# GitHub Pagesへのデプロイ手順

このリポジトリの `install.sh` をGitHub Pagesで配信し、`https://get-ros2.com/install.sh` から取得できるようにする手順です。

このプロジェクトはROS 2の公式インストーラーではありません。READMEとスクリプトの非公式表記、インストール前の確認メッセージを維持して公開してください。

## 1. リポジトリをGitHubへpushする

GitHub上にリポジトリを作成し、このプロジェクトの `main` ブランチをpushします。初回の例です。`OWNER` と `REPOSITORY` は実際の値に置き換えてください。

```sh
git add install.sh README.md LICENSE HowToDeploy.md tests .github
git commit -m "Add ROS 2 installer and CI"
git remote add origin https://github.com/OWNER/REPOSITORY.git
git push -u origin main
```

既に `origin` がある場合は追加不要です。`git remote -v` で接続先を確認してください。

## 2. GitHub Pagesを設定する

1. リポジトリの **Settings → Pages** を開きます。
2. **Build and deployment → Source** で **GitHub Actions** を選択します。
3. **Custom domain** に `get-ros2.com` を入力して保存します。
4. **Settings → Environments → github-pages → Deployment branches and tags** を確認します。選択したブランチ・タグだけを許可する設定の場合は、手動実行用のブランチ `main` に加え、正式リリースで使うタグの規則（例：`v*`）を追加します。タグはブランチと別のルールとして登録してください。リリース時の自動デプロイはタグから実行されるため、`main` だけの許可では止まります。

Actionsから公開する場合、`CNAME` ファイルは使われません。ドメインは必ずPages設定画面で登録し、その後にDNSを設定してください。[GitHub公式の独自ドメイン設定](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)も参照してください。

## 3. DNSとHTTPSを設定する

この操作は、`get-ros2.com` の接続先としてGitHub Pagesを登録するものです。DNSはドメイン名から接続先のIPアドレスを調べる仕組みで、Aレコードはドメイン名とIPv4アドレスの対応を登録します。

次の4つは、GitHubが[公式ドキュメントで指定しているGitHub Pages用のIPアドレス](https://docs.github.com/ja/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)です。GitHub Pagesの共通の配信先なので、この値をそのまま使います。

`get-ros2.com` のDNSを管理しているサービスの設定画面で、次の4件を登録します。ホスト名の `@` は、ドメインそのもの、ここでは `get-ros2.com` を表します。入力形式はサービスによって異なり、空欄やドメイン名の入力を指定される場合もあります。

種類は `A`、ホスト名は `@` とし、値には次のIPアドレスを1件ずつ設定します。

```text
185.199.108.153
185.199.109.153
185.199.110.153
185.199.111.153
```

続いて、`www.get-ros2.com` 用に種類 `CNAME`、ホスト名 `www` のレコードを追加します。値は次のとおりです。

```text
mrbearing.github.io
```

GitHub Pagesの **Custom domain** は `get-ros2.com` にします。この設定により、`www.get-ros2.com` へのアクセスも `get-ros2.com` へ転送されます。CNAMEの値には `https://` やリポジトリ名の `/get-ros2` を含めません。

`www.get-ros2.com is improperly configured` と表示された場合は、このCNAMEレコードを確認してください。保存後、DNSの反映を待ってPages設定画面で再チェックします。反映には最大24時間かかる場合があります。

公開と設定が完了すると、ファイルの取得は次の流れになります。

1. 利用者の `curl` が、DNSで `get-ros2.com` のIPアドレスを調べます。
2. 取得したIPアドレスを使ってGitHub Pagesに接続し、`get-ros2.com` の `/install.sh` を要求します。
3. GitHub Pagesが、手順2の **Custom domain** 設定で紐づけた `MrBearing/get-ros2` の公開サイトから `install.sh` を返します。

DNSの設定は「GitHub Pagesへ接続するため」、Custom domainの設定は「どのリポジトリの公開サイトを配信するかを紐づけるため」に必要です。

DNSが反映され、証明書が発行されたら、Pages設定の **Enforce HTTPS** を有効化します。DNSの確認には次のコマンドを使用できます。

```sh
dig get-ros2.com +short A
dig www.get-ros2.com +short CNAME
```

利用者には次のコマンドを案内してください。

```sh
curl -fsSL https://get-ros2.com/install.sh | sh
```

`curl get-ros2.com/install.sh | sh` ではHTTPからHTTPSへの転送を追わないため、`https://` と `-fsSL` が必要です。

## 4. OS別CIとデプロイを実行する

`main` へのpushで、次の3つの独立したワークフローが起動します。PRでも各OSのチェックを実行します。

`main` へのマージ・pushとCI完了だけでは、公開中のスクリプトは更新されません。

| Ubuntu | リポジトリ版CI | 公開版CI |
| --- | --- | --- |
| 22.04 | `ci-ubuntu-22-04.yml` | `published-ubuntu-22-04.yml` |
| 24.04 | `ci-ubuntu-24-04.yml` | `published-ubuntu-24-04.yml` |
| 26.04 | `ci-ubuntu-26-04.yml` | `published-ubuntu-26-04.yml` |

READMEには、それぞれのワークフローに対応する計6個のバッジがあります。リンク先は `MrBearing/get-ros2` です。別のリポジトリで運用する場合は、READMEのバッジURLを変更してください。

共通の `check-ubuntu.yml` が、対象OSのコンテナで次の処理を行います。

1. リポジトリ版はcheckoutした `install.sh`、公開版は `https://get-ros2.com/install.sh` を取得して使用。取得処理自体も、成功・DNSエラー・HTTPエラー・タイムアウト・空応答・HTML・途中で切れたスクリプトの7パターンをテスト。
2. 構文チェックとShellCheckを実行。
3. パッケージマネージャーをテスト用コマンドに差し替え、DNS・TLS・署名・ロック・依存関係・チェックサムなど19パターンの失敗を意図的に発生させる。一時ファイル名に `tlS` や `404` が含まれても誤判定しないことも確認する。インストーラー本体は変更せず、終了コード、エラーメッセージ全文、元のログ、失敗後に後続処理が動かないことを検証。
4. 別の隔離したテスト用コピーで、OS・CPU判定、チェックサム不一致、sudo、確認プロンプト、パイプ実行などを検証。テストはBashとExpectで実装し、Pythonを使わない。
5. 検証した元ファイルをartifactとして保存し、その同じファイルを使って `ros-base` と `desktop` をクリーンなコンテナに実インストール。

各OSで、`tests/release-deploy.sh` によるデプロイ条件のテストも実行します。GitHub APIをテスト用コマンドに置き換え、正式リリース、注釈付きタグ、CI失敗、タグ変更などを検証します。このテストがリリースを作成したり、実際にデプロイしたりすることはありません。

成功時のインストールには `--yes` を指定します。通常の利用者には、sudo認証やシステム変更より前に英語の確認プロンプトが表示されます。CIはamd64で実行します。arm64の判定は回帰テストで確認しますが、arm64実機・GUI・実機通信は対象外です。

### 公開の条件

GitHub Releaseの公開（`release: published`）で **Deploy installer** が起動します。正式リリースだけを対象とし、下書き・プレリリースは公開対象にしません。プレリリースの公開でワークフローが起動した場合は、ジョブをスキップします。

`.github/scripts/verify-release.sh` が、公開済みリリースとそのタグをAPIで取得し、タグが指すコミットSHAを確定します。軽量タグと注釈付きタグの両方に対応します。リリースの `target_commitish` や現在の `main` の先頭から公開対象を推測しません。

そのSHAに対する、3つのOS別ワークフローの `main` push時の実行結果を確認します。各ワークフローの最新の該当実行がすべて完了・成功している場合だけ、そのSHAのファイルを公開します。PRの成功や別SHAの結果では代用しません。CIが未完了・失敗・未実行の場合やAPIにアクセスできない場合は、エラーと理由を表示して停止します。

環境の承認待ちやファイル準備の間に状態が変わる場合に備え、実際の公開直前にも同じ検証を実行します。リリースのID、タグのコミット、CI結果が条件を満たさなくなった場合は公開を止めます。検証済みの過去の正式リリースは、`main` に新しい変更があっても手動で再配布できます。

### 正式リリースを公開する

1. このデプロイワークフローの変更を含め、公開したい変更を `main` へマージします。
2. 対象コミットの **CI Ubuntu 22.04 / 24.04 / 26.04** がすべて成功するまで待ちます。
3. GitHubの **Releases → Draft a new release** で、その検証済みコミットを指すタグ（例：`v1.0.0`）を選びます。タグのコミットSHAが、CIで検証されたSHAと一致することを確認してください。
4. プレリリース指定を外し、**Publish release** を実行します。
5. **Deploy installer** の `gate`、`deploy`、`check-published` と、その後に起動する公開版CIの結果を確認します。

CI完了前にリリースを公開するとデプロイは停止します。後からCIが成功しても自動再実行はしないため、次の手順で再実行してください。

### 公開済みリリースを手動で再デプロイする

**Actions → Deploy installer → Run workflow** で、実行ブランチに `main` を選択し、必須入力の `release_tag` に公開済みの正式リリースのタグを指定します。GitHub CLIでも実行できます。

```sh
gh workflow run deploy.yml --repo MrBearing/get-ros2 --ref main -f release_tag=v1.0.0
```

タグだけが存在しても、GitHub Releaseが未公開・下書き・プレリリースの場合はデプロイしません。手動実行でも、対象コミットの全OSのCI成功が必要です。`main` 以外のブランチからの手動実行はスキップします。

### 配信するファイル

リリースタグから確定したコミットのファイルをGitHub Pagesへ配信します。

| ファイル | 用途 |
| --- | --- |
| `install.sh` | インストーラー本体 |
| `install.sh.sha256` | 公開するスクリプトのSHA-256 |
| `README.md` | 英語の利用説明 |
| `LICENSE` | MITライセンス全文 |
| `.nojekyll` | 静的ファイルとして配信するための設定 |

`HowToDeploy.md` とテストコードは配信対象に含めません。公開処理は `.github/workflows/deploy.yml` にあります。

### 公開版の継続チェック

デプロイ成功後、Actionsの `workflow_dispatch` APIで3つの公開版CIを起動します。このため、起動用ジョブに `actions: write` を付与しています。公開版CI自体は `contents: read` で実行します。

公開版CIは毎日（UTC 03:11 / 03:21 / 03:31）にも実行し、手動実行も可能です。ファイルの取得失敗、空の応答、シェルスクリプトではない応答も失敗として扱います。取得できない場合にローカルのファイルへ切り替えることはありません。DNSとHTTPSが利用可能になるまでは、公開版のバッジは成功になりません。

## 5. 公開結果を確認する

```sh
curl -fsSL https://get-ros2.com/install.sh -o /tmp/get-ros2-install.sh
sh -n /tmp/get-ros2-install.sh
sh /tmp/get-ros2-install.sh --dry-run
```

`--dry-run` で、非公式である旨、OSの検出結果、実行予定が英語で表示されることを確認します。この操作では確認プロンプトやインストール処理は実行されません。

配信ファイルの照合用に `https://get-ros2.com/install.sh.sha256` も公開します。同じ配信元のチェックサムは転送・公開内容の確認用であり、独立した署名ではありません。

## 更新と公開失敗時の確認

スクリプトや説明を更新したら、PRのCI結果を確認してから `main` へ反映し、対象コミットの全OSのCI成功後に正式リリースを公開します。対応OSを増やす場合は、スクリプト、READMEのバッジ・対応表、OS別ワークフロー、`.github/scripts/verify-release.sh` のワークフロー一覧、テストを合わせて更新してください。

- テストが失敗した場合は、そのジョブのログを確認してください。全チェックが成功するまでデプロイは開始されません。
- デプロイだけが失敗した場合は、PagesのSourceが **GitHub Actions** になっているか、`github-pages` 環境の保護設定を確認してください。
- `Get Pages site failed` / `Not Found` が出た場合は、手順2のPages設定を確認し、公開済みリリースのタグを指定して再実行してください。
- `github-pages` 環境でタグからのデプロイが拒否された場合は、手順2のタグ許可ルールを確認してください。
- リリースやCIの検証が失敗した場合は、`gate` または公開直前の再検証が失敗し、Summaryに理由が表示されます。CI完了・失敗の解消後、同じ公開済みリリースを指定して再実行してください。
- Node.jsの非推奨警告とテストの失敗は別々に確認してください。利用するActionsはNode.js 24対応版に更新しています。
- ドメインへ接続できない場合は、PagesのCustom domain、DNSレコード、証明書の発行状態を確認してください。

初回リリース時にPages設定が間に合わなかった場合は、設定後に、その公開済みリリースのタグを指定して **Deploy installer** を再実行してください。
