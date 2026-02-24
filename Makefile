.PHONY: setup-models setup-fallback setup

setup: setup-models setup-fallback

setup-models:
	mkdir -p mascot/assets/models/blend_shape mascot/assets/models/blend_shape_mini mascot/assets/models/parts
	cp -n mascot/config/examples/blend_shape.toml mascot/assets/models/blend_shape/emotions.toml 2>/dev/null || true
	cp -n mascot/config/examples/blend_shape_mini.toml mascot/assets/models/blend_shape_mini/emotions.toml 2>/dev/null || true
	cp -n mascot/config/examples/parts.toml mascot/assets/models/parts/emotions.toml 2>/dev/null || true
	@if command -v gh >/dev/null 2>&1; then \
		gh release download v0.03 --repo sawarae/utsutsu2d --dir mascot/assets/models/blend_shape --pattern '*.inp' --clobber; \
	else \
		echo "gh CLI not found, using curl fallback..."; \
		curl -sL "https://api.github.com/repos/sawarae/utsutsu2d/releases/tags/v0.03" | \
		python3 -c "import json,sys,urllib.request; release=json.load(sys.stdin); [urllib.request.urlretrieve(a['browser_download_url'], 'mascot/assets/models/blend_shape/'+a['name']) or print('Downloaded '+a['name']) for a in release['assets'] if a['name'].endswith('.inp')]"; \
	fi
	@cp -f mascot/assets/models/blend_shape/*_mini.inp mascot/assets/models/blend_shape_mini/ 2>/dev/null || true

setup-fallback:
	mkdir -p mascot/assets/fallback
	@if command -v gh >/dev/null 2>&1; then \
		gh release download v0.03 --repo sawarae/utsutsu-code --dir mascot/assets/fallback --pattern '*.png' --clobber; \
	else \
		echo "gh CLI not found, using curl fallback..."; \
		curl -sL "https://api.github.com/repos/sawarae/utsutsu-code/releases/tags/v0.03" | \
		python3 -c "import json,sys,urllib.request; release=json.load(sys.stdin); [urllib.request.urlretrieve(a['browser_download_url'], 'mascot/assets/fallback/'+a['name']) or print('Downloaded '+a['name']) for a in release['assets'] if a['name'].endswith('.png')]"; \
	fi
