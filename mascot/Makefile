.PHONY: setup-models setup-fallback setup clean clean-build clean-signal clean-assets clean-hooks

setup: setup-models setup-fallback

setup-models:
	mkdir -p assets/models/blend_shape assets/models/blend_shape_mini assets/models/parts
	cp -n config/examples/blend_shape.toml assets/models/blend_shape/emotions.toml 2>/dev/null || true
	cp -n config/examples/blend_shape_mini.toml assets/models/blend_shape_mini/emotions.toml 2>/dev/null || true
	cp -n config/examples/parts.toml assets/models/parts/emotions.toml 2>/dev/null || true
	@if command -v gh >/dev/null 2>&1; then \
		gh release download v0.03 --repo sawarae/utsutsu2d --dir assets/models/blend_shape --pattern '*.inp' --clobber; \
	else \
		echo "gh CLI not found, using curl fallback..."; \
		curl -sL "https://api.github.com/repos/sawarae/utsutsu2d/releases/tags/v0.03" | \
		python3 -c "import json,sys,urllib.request; release=json.load(sys.stdin); [urllib.request.urlretrieve(a['browser_download_url'], 'assets/models/blend_shape/'+a['name']) or print('Downloaded '+a['name']) for a in release['assets'] if a['name'].endswith('.inp')]"; \
	fi
	@cp -f assets/models/blend_shape/*_mini.inp assets/models/blend_shape_mini/ 2>/dev/null || true

setup-fallback:
	mkdir -p assets/fallback
	@if command -v gh >/dev/null 2>&1; then \
		gh release download v0.03 --repo sawarae/utsutsu-code --dir assets/fallback --pattern '*.png' --clobber; \
	else \
		echo "gh CLI not found, using curl fallback..."; \
		curl -sL "https://api.github.com/repos/sawarae/utsutsu-code/releases/tags/v0.03" | \
		python3 -c "import json,sys,urllib.request; release=json.load(sys.stdin); [urllib.request.urlretrieve(a['browser_download_url'], 'assets/fallback/'+a['name']) or print('Downloaded '+a['name']) for a in release['assets'] if a['name'].endswith('.png')]"; \
	fi

clean: clean-build clean-signal
	@echo "Clean complete. Run 'make clean-assets' or 'make clean-hooks' separately."

clean-build:
	rm -rf build
	@echo "Removed build/"

clean-signal:
	rm -f ~/.claude/utsutsu-code/mascot_speaking
	rm -f ~/.claude/utsutsu-code/mascot_listening
	@echo "Removed stale signal files"

clean-assets:
	rm -f assets/models/blend_shape/*.inp
	rm -f assets/models/blend_shape_mini/*.inp
	rm -f assets/models/parts/*.inp
	rm -f assets/fallback/*.png
	@echo "Removed downloaded assets (run 'make setup' to re-download)"

clean-hooks:
	rm -f ~/.claude/hooks/mascot_tts.py
	rm -f ~/.claude/hooks/tts_config.toml
	@echo "Removed global hooks (run /tsukuyomi-setup to re-create)"
