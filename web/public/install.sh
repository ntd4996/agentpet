#!/bin/sh
# AgentPet one-line installer for Linux (x86_64).
#   curl -fsSL https://agentpet.thenightwatcher.online/install.sh | sh
# Downloads the latest AppImage to ~/.local/bin , no root, works on any distro.
set -eu

REPO="ntd4996/agentpet"
DEST="${HOME}/.local/bin"
APP="${DEST}/AgentPet.AppImage"

case "$(uname -m)" in
  x86_64|amd64) ;;
  *) echo "AgentPet Linux builds are x86_64 only for now (you have $(uname -m))." >&2; exit 1 ;;
esac

echo "Finding the latest AgentPet Linux release..."
TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases" \
  | grep -o '"tag_name": *"linux-v[^"]*"' | head -1 \
  | sed 's/.*: *"//; s/"//')
[ -n "${TAG:-}" ] || { echo "Could not find a linux-v* release." >&2; exit 1; }
VER="${TAG#linux-v}"
URL="https://github.com/${REPO}/releases/download/${TAG}/AgentPet_${VER}_amd64.AppImage"

echo "Downloading AgentPet ${VER}..."
mkdir -p "${DEST}"
curl -fL "${URL}" -o "${APP}"
chmod +x "${APP}"

echo "Installed to ${APP}"
case ":${PATH}:" in
  *":${DEST}:"*) ;;
  *) echo "Tip: add ${DEST} to your PATH to run 'AgentPet.AppImage' from anywhere." ;;
esac
echo "Launching..."
( "${APP}" >/dev/null 2>&1 & )
echo "Done. AgentPet ${VER} is running."
