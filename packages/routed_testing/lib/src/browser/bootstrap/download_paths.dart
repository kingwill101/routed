// Map of browser download paths for different platforms and architectures
final downloadPaths = {
  'chromium': {
    '': null,
    'ubuntu18.04-x64': null,
    'ubuntu20.04-x64': 'builds/chromium/%s/chromium-linux.zip',
    'ubuntu22.04-x64': 'builds/chromium/%s/chromium-linux.zip',
    'ubuntu24.04-x64': 'builds/chromium/%s/chromium-linux.zip',
    'debian11-x64': 'builds/chromium/%s/chromium-linux.zip',
    'debian12-x64': 'builds/chromium/%s/chromium-linux.zip',
    'debian11-arm64': 'builds/chromium/%s/chromium-linux-arm64.zip',
    'debian12-arm64': 'builds/chromium/%s/chromium-linux-arm64.zip',
    'mac10.15': 'builds/chromium/%s/chromium-mac.zip',
    'mac11': 'builds/chromium/%s/chromium-mac.zip',
    'mac11-arm64': 'builds/chromium/%s/chromium-mac-arm64.zip',
    'mac12': 'builds/chromium/%s/chromium-mac.zip',
    'mac12-arm64': 'builds/chromium/%s/chromium-mac-arm64.zip',
    'mac13': 'builds/chromium/%s/chromium-mac.zip',
    'mac13-arm64': 'builds/chromium/%s/chromium-mac-arm64.zip',
    'win64': 'builds/chromium/%s/chromium-win64.zip',
  },
  'firefox': {
    '': null,
    'ubuntu18.04-x64': null,
    'ubuntu20.04-x64': 'builds/firefox/%s/firefox-ubuntu-20.04.zip',
    'ubuntu22.04-x64': 'builds/firefox/%s/firefox-ubuntu-22.04-x64.zip',
    'ubuntu24.04-x64': 'builds/firefox/%s/firefox-ubuntu-24.04-x64.zip',
    'debian11-x64': 'builds/firefox/%s/firefox-debian-11-x64.zip',
    'debian12-x64': 'builds/firefox/%s/firefox-debian-12-x64.zip',
    'debian11-arm64': 'builds/firefox/%s/firefox-debian-11-arm64.zip',
    'debian12-arm64': 'builds/firefox/%s/firefox-debian-12-arm64.zip',
    'mac10.15': 'builds/firefox/%s/firefox-mac.zip',
    'mac11': 'builds/firefox/%s/firefox-mac.zip',
    'mac11-arm64': 'builds/firefox/%s/firefox-mac-arm64.zip',
    'mac12': 'builds/firefox/%s/firefox-mac.zip',
    'mac12-arm64': 'builds/firefox/%s/firefox-mac-arm64.zip',
    'mac13': 'builds/firefox/%s/firefox-mac.zip',
    'mac13-arm64': 'builds/firefox/%s/firefox-mac-arm64.zip',
    'win64': 'builds/firefox/%s/firefox-win64.zip',
  },
};

final executablePaths = {
  'chromium': {
    'linux': ['chrome-linux', 'chrome'],
    'mac': ['chrome-mac', 'Chromium.app', 'Contents', 'MacOS', 'Chromium'],
    'win': ['chrome-win', 'chrome.exe'],

 },
  'firefox': {
    'linux': ['firefox', 'firefox'],
    'mac': ['firefox', 'Nightly.app', 'Contents', 'MacOS', 'firefox'],
    'win': ['firefox', 'firefox.exe'],
  },
};

final playwrightCdnMirrors = [
  'https://playwright.azureedge.net',
  'https://playwright-akamai.azureedge.net',
  'https://playwright-verizon.azureedge.net',
]; 