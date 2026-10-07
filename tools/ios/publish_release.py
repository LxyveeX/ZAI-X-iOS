#!/usr/bin/env python3
"""Archive a successful iOS build without rebuilding or replacing published files."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ARTIFACT_NAME = 'ZAI-X-iOS-unsigned'
WORKFLOW_PATH = '.github/workflows/build_ios.yml'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def gh(*args):
    return subprocess.run(
        ['gh', *map(str, args)], check=True, capture_output=True, text=True
    ).stdout


def api(endpoint, missing_ok=False):
    try:
        return json.loads(gh('api', endpoint))
    except subprocess.CalledProcessError as error:
        if missing_ok and 'HTTP 404' in error.stderr:
            return None
        raise


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def validate_run(run, repository):
    require(run.get('status') == 'completed' and run.get('conclusion') == 'success',
            'The iOS build must have completed successfully.')
    require(run.get('path') == WORKFLOW_PATH, 'Unexpected build workflow.')
    require(run.get('event') in ('push', 'workflow_dispatch'), 'Unsupported build event.')
    require(run.get('head_branch') in ('main', 'zaimanhua', 'ios-port'),
            'Unexpected build branch.')
    for key in ('repository', 'head_repository'):
        require(run.get(key, {}).get('full_name') == repository,
                'Build must originate in this repository.')
    require(re.fullmatch(r'[0-9a-f]{40}', run.get('head_sha', '')), 'Invalid source SHA.')
    for key in ('id', 'run_number', 'run_attempt'):
        require(isinstance(run.get(key), int) and run[key] > 0, f'Invalid {key}.')


def validate_artifact(folder, run, repository):
    info = json.loads((folder / 'build-info.json').read_text())
    require(info.get('repository') == repository, 'Artifact repository mismatch.')
    require(info.get('source_commit') == run['head_sha'], 'Artifact source mismatch.')
    version = info.get('version', '')
    require(re.fullmatch(r'\d+\.\d+\.\d+', version), 'Unexpected app version.')
    require(re.fullmatch(r'\d+', str(info.get('build', ''))), 'Invalid app build number.')
    require(info.get('signed') is False, 'Only unsigned IPA files are published here.')
    require(re.fullmatch(r'\d+\.\d+(?:\.\d+)?', info.get('minimum_ios', '')),
            'Invalid minimum iOS version.')
    require(re.fullmatch(r'[A-Za-z0-9.-]+', info.get('bundle_identifier', '')),
            'Invalid bundle identifier.')
    require(info.get('device_families') == [1, 2], 'Expected iPhone and iPad support.')
    ipa = folder / f'ZAI-X-iOS-{version}-unsigned.ipa'
    assets = [ipa, folder / 'SHA256SUMS.txt', folder / 'build-info.json',
              folder / 'simulator-check.json', folder / 'ipad-startup.png']
    require(all(path.is_file() and not path.is_symlink() and path.stat().st_size > 0
                for path in assets), 'A required release file is missing or empty.')
    digest = sha256(ipa)
    require(info.get('sha256') == digest, 'IPA SHA-256 does not match build-info.json.')
    require((folder / 'SHA256SUMS.txt').read_text().strip() == f'{digest}  {ipa.name}',
            'IPA SHA-256 does not match SHA256SUMS.txt.')
    smoke = json.loads((folder / 'simulator-check.json').read_text())
    require(smoke.get('alive_after_seconds', 0) >= 15 and
            smoke.get('launch', '').startswith(info['bundle_identifier'] + ':'),
            'Missing successful simulator startup check.')
    return info, assets


def ensure_tag(repository, tag, source_sha):
    ref = api(f'repos/{repository}/git/ref/tags/{tag}', missing_ok=True)
    if ref is None:
        ref = json.loads(gh('api', '--method', 'POST',
                            f'repos/{repository}/git/refs',
                            '-f', f'ref=refs/tags/{tag}', '-f', f'sha={source_sha}'))
    target = ref['object']
    if target['type'] == 'tag':
        target = api(f'repos/{repository}/git/tags/{target["sha"]}')['object']
    require(target['type'] == 'commit' and target['sha'] == source_sha,
            'Release tag points to a different source commit.')


def verify_asset(repository, remote, local):
    require(remote['size'] == local.stat().st_size, f'Asset size mismatch: {local.name}')
    digest = remote.get('digest')
    if not digest:
        # Older release assets may not have a server-side digest.
        with tempfile.TemporaryFile() as stream:
            subprocess.run(
                ['gh', 'api', '-H', 'Accept: application/octet-stream',
                 f'repos/{repository}/releases/assets/{remote["id"]}'],
                check=True, stdout=stream,
            )
            stream.seek(0)
            digest = 'sha256:' + hashlib.file_digest(stream, 'sha256').hexdigest()
    require(digest == 'sha256:' + sha256(local), f'Asset SHA-256 mismatch: {local.name}')


def release_notes(info, run, repository):
    root = f'https://github.com/{repository}'
    return f'''ZAI-X 个人自用 iOS / iPadOS 适配 · 自动构建存档

**预览版：已通过构建流程中的检查，尚未完成真机验证。**
模拟器启动检查不代表签名安装、登录、阅读、通知及照片权限已在实际设备上验证。

### 下载与安装

在下方 Assets 下载 `ZAI-X-iOS-{info['version']}-unsigned.ipa`，导入自己的签名工具，
使用有效证书与描述文件签名后安装。

- 版本：{info['version']} ({info['build']})
- 支持设备：iPhone / iPad；最低系统：iOS / iPadOS {info['minimum_ios']}
- 应用标识：`{info['bundle_identifier']}`；首次使用需要重新登录
- [安装说明]({root}/blob/zaimanhua/docs/IOS.md)
- [原始构建 #{run['run_number']}]({root}/actions/runs/{run['id']}) · 第 {run['run_attempt']} 次运行
- 构建提交：[{run['head_sha'][:7]}]({root}/commit/{run['head_sha']})

### 校验与留档

IPA SHA-256：

```text
{info['sha256']}
```

本次发布直接保存上述成功构建的产物，没有重新打包 IPA。附件同时包含校验文件、
构建信息、模拟器启动记录和 iPad 截图。每次成功构建单独留档，旧版本继续保留。
预览版请在 Releases 手动下载；App 内的更新检查只读取正式版。

基于 [funkeyyou/zaimanhua](https://github.com/funkeyyou/zaimanhua)，
保留原项目及贡献者署名，源码沿用 [GPL-3.0 许可证]({root}/blob/zaimanhua/LICENSE)。
'''


def publish(repository, run_id):
    require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository),
            'Invalid repository name.')
    if not run_id:
        result = api(f'repos/{repository}/actions/workflows/build_ios.yml/runs?'
                     'status=success&per_page=1')
        require(result['workflow_runs'], 'No successful iOS build was found.')
        run_id = str(result['workflow_runs'][0]['id'])
    require(re.fullmatch(r'\d+', run_id), 'Build run ID must be numeric.')
    run = api(f'repos/{repository}/actions/runs/{run_id}')
    validate_run(run, repository)
    listing = api(f'repos/{repository}/actions/runs/{run_id}/artifacts?per_page=100')
    artifacts = [item for item in listing['artifacts'] if item['name'] == ARTIFACT_NAME]
    require(len(artifacts) == 1 and not artifacts[0]['expired'],
            'Expected exactly one unexpired iOS artifact.')

    with tempfile.TemporaryDirectory(prefix='zai-ios-release-') as temp:
        folder = Path(temp)
        gh('run', 'download', run_id, '--repo', repository,
           '--name', ARTIFACT_NAME, '--dir', folder)
        info, assets = validate_artifact(folder, run, repository)
        # The ios- prefix avoids the upstream Android/Windows v* release trigger.
        tag = (f'ios-v{info["version"]}-run{run["run_number"]}-'
               f'{run["id"]}-a{run["run_attempt"]}')
        ensure_tag(repository, tag, run['head_sha'])
        endpoint = f'repos/{repository}/releases/tags/{tag}'
        release = api(endpoint, missing_ok=True)
        if release is None:
            notes = folder / 'release-notes.md'
            notes.write_text(release_notes(info, run, repository), encoding='utf-8')
            gh('release', 'create', tag, '--repo', repository, '--draft', '--prerelease',
               '--latest=false', '--target', run['head_sha'],
               '--title', f'iOS {info["version"]} · 构建 #{run["run_number"]}（预览版）',
               '--notes-file', notes)
            release = api(endpoint)

        require(release['prerelease'], 'Refusing to change an existing stable release.')
        remote_assets = {asset['name']: asset for asset in release['assets']}
        for local in assets:
            if local.name in remote_assets:
                verify_asset(repository, remote_assets[local.name], local)
            else:
                require(release['draft'], 'Published release is missing an expected asset.')
                gh('release', 'upload', tag, local, '--repo', repository)

        release = api(endpoint)
        remote_assets = {asset['name']: asset for asset in release['assets']}
        for local in assets:
            require(local.name in remote_assets, f'Upload missing: {local.name}')
            verify_asset(repository, remote_assets[local.name], local)
        if release['draft']:
            gh('release', 'edit', tag, '--repo', repository,
               '--draft=false', '--prerelease', '--latest=false')
        release = api(endpoint)
        require(not release['draft'] and release['prerelease'], 'Release is not published.')
        print(release['html_url'])
        summary = os.environ.get('GITHUB_STEP_SUMMARY')
        if summary:
            with open(summary, 'a', encoding='utf-8') as stream:
                stream.write(f'IPA 已留档：[iOS {info["version"]} 预览版]({release["html_url"]})\n\n'
                             f'源构建 #{run["run_number"]}，SHA-256：`{info["sha256"]}`\n')


if __name__ == '__main__':
    try:
        publish(os.environ['GITHUB_REPOSITORY'], os.environ.get('BUILD_RUN_ID', '').strip())
    except subprocess.CalledProcessError as error:
        print(error.stderr, file=sys.stderr)
        raise
