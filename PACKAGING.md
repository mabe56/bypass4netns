# Debian Package Creation and Distribution

This directory contains scripts for creating, uploading, and installing bypass4netns as a Debian package.


## Quick Start

```bash
# 1. Build the package
cd /home/foo/bypass4netns
./create-deb.sh

# 2. Upload to GitLab (set your credentials first)
export GITLAB_URL=https://gitlab.com
export GITLAB_PROJECT_ID=your_project_id
export GITLAB_TOKEN=your_token
./upload-package.sh bypass4netns_*.deb

# Or
set -a
source .env
set +a
./upload-package.sh bypass4netns_*.deb

# 3. On target machine - install
sudo -E ./install-from-gitlab.sh
```


## Detailed Usage

### Creating a Package

The `create-deb.sh` script creates a Debian package with:
- **Binaries**: `/usr/local/bin/bypass4netns` and `bypass4netnsd`
- **Documentation**: `/usr/share/doc/bypass4netns/`
- **Dependencies**: `libseccomp2 (>= 2.5.0)`
- **Post-install scripts**: Ensures correct permissions
- **Checksums**: SHA256 and MD5 for verification

**Requirements:**
- `dpkg` for package building
- `git` for version detection
- Binaries already built or ability to run `make static strip`

**Output files:**
```
bypass4netns_1.0.0_amd64.deb        # The Debian package
bypass4netns_1.0.0_amd64.deb.sha256 # SHA256 checksum
bypass4netns_1.0.0_amd64.deb.md5    # MD5 checksum
```


### Uploading to GitLab

The `upload-package.sh` script uploads packages to GitLab's Generic Package Registry.

**Get a GitLab Personal Access Token:**
1. Go to `https://<your-gitlab-instance>/-/user_settings/personal_access_tokens`
2. Create a new token with `api` scope
3. Save the token securely

**Find your Project ID:**
- Go to your project → Settings → General
- Look for "Project ID"

**Upload options:**
```bash
# Using environment variables (recommended)
export GITLAB_URL=https://gitlab.com
export GITLAB_PROJECT_ID=123
export GITLAB_TOKEN=glpat-xxxxxxxxxxxx
./upload-package.sh bypass4netns_1.0.0_amd64.deb

# With .env file
set -a
source .env
set +a
./upload-package.sh bypass4netns_1.0.0_amd64.deb

# Using command-line arguments
./upload-package.sh \
  -u https://gitlab.com \
  -p 123 \
  -t glpat-xxx \
  bypass4netns_1.0.0_amd64.deb
```

The script will:
- Upload the `.deb` file
- Upload checksums (`.sha256`, `.md5`)
- Display download URL and installation command


### Installing from GitLab

The `install-from-gitlab.sh` script downloads and installs packages from GitLab.

**Basic installation:**
```bash
# Latest version
export GITLAB_PROJECT_ID=123
export GITLAB_TOKEN=glpat-xxx
export GITLAB_URL=https://gitlab.com
sudo -E ./install-from-gitlab.sh

# With .env file
set -a
source .env
set +a
sudo -E ./install-from-gitlab.sh

# Specific version
sudo -E ./install-from-gitlab.sh -v 1.0.0
```

**Options:**
- `--download-only`: Download without installing (useful for inspection)
- `--verify`: Verify SHA256 checksum after download
- `-v VERSION`: Specify version (default: latest)

**Examples:**
```bash
# Download only (no sudo needed)
./install-from-gitlab.sh -p 123 -t glpat-xxx --download-only

# Install with checksum verification
sudo -E ./install-from-gitlab.sh --verify

# Install specific version
sudo -E ./install-from-gitlab.sh -v 0.9.0
```

**Note on sudo -E:**
The `-E` flag preserves environment variables when using sudo, so `GITLAB_TOKEN` and other variables are passed through.


## Version Management

**Semantic versioning from git tags:**
```bash
# Tag a release
git tag -a v1.0.0 -m "Release 1.0.0"
git push origin v1.0.0

# Build will automatically use the tag as version
./create-deb.sh
# Creates: bypass4netns_1.0.0_amd64.deb
```

**List available versions in GitLab:**
```bash
curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/packages?package_name=bypass4netns"
```


## Troubleshooting

### Package creation fails
```bash
# Clean and rebuild
make clean
make static strip
./create-deb.sh
```

### Upload fails with 401 Unauthorized
- Check if token is valid and has `api` scope
- Verify token hasn't expired

### Upload fails with 404 Not Found
- Verify project ID is correct
- Check if Generic Package Registry is enabled in project settings

### Installation fails with dependency errors
```bash
# Install dependencies manually
sudo apt-get update
sudo apt-get install -y libseccomp2

# Try again
sudo apt install ./bypass4netns_*.deb
```

### Cannot fetch latest version
```bash
# Specify version explicitly
sudo -E ./install-from-gitlab.sh -v 1.0.0
```


## CI/CD Integration

For automated package creation in GitLab CI, add to `.gitlab-ci.yml`:

```yaml
variables:
  PACKAGE_REGISTRY_URL: "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/bypass4netns/${CI_COMMIT_TAG}"

build-and-upload-deb:
  stage: deploy
  image: debian:13-slim
  before_script:
    - apt-get update && apt-get install -y build-essential git curl dpkg-dev
  script:
    - ./create-deb.sh
    - |
      curl --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
           --upload-file bypass4netns_*.deb \
           "${PACKAGE_REGISTRY_URL}/bypass4netns_${CI_COMMIT_TAG#v}_amd64.deb"
  only:
    - tags
  artifacts:
    paths:
      - "*.deb"
      - "*.deb.sha256"
    expire_in: 1 year
```


## Manual Installation (Without Scripts)

If you prefer manual installation:

```bash
# Download
curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
     "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/packages/generic/bypass4netns/1.0.0/bypass4netns_1.0.0_amd64.deb" \
     -o bypass4netns.deb

# Install
sudo apt install ./bypass4netns.deb

# Verify
bypass4netns --version
```


## Uninstallation

```bash
# Remove package
sudo apt remove bypass4netns

# Purge (including configuration)
sudo apt purge bypass4netns
```


## Security Notes

- **Never commit tokens** to git repositories
- Use GitLab CI/CD variables for tokens in pipelines
- Rotate tokens regularly
- Use project tokens or group tokens with minimal required permissions
- Consider using `.netrc` file for curl authentication in production environments


## Support

For issues with the packaging scripts, check:
1. Script has execute permissions: `chmod +x *.sh`
2. All dependencies are installed
3. GitLab credentials are correct
4. Network connectivity to GitLab server
