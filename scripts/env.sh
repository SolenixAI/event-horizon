#!/usr/bin/env bash
# Source this file to ensure developer and agent toolchains are on PATH:
#   source scripts/env.sh

case ":$PATH:" in
  *":/opt/homebrew/bin:"*) ;;
  *) [ -d "/opt/homebrew/bin" ] && export PATH="/opt/homebrew/bin:$PATH" ;;
esac

case ":$PATH:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) [ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH" ;;
esac
