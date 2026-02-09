.PHONY: setup-models setup-fallback setup

setup: setup-models setup-fallback

setup-models:
	mkdir -p assets/models/blend_shape assets/models/parts
	cp config/examples/blend_shape.toml assets/models/blend_shape/emotions.toml
	cp config/examples/parts.toml assets/models/parts/emotions.toml
	gh release download v0.01 --repo sawarae/utsutsu2d --dir assets/models/blend_shape --pattern '*.inp' --clobber
	@mv -f assets/models/blend_shape/tsukuyomi_blend_shape.inp assets/models/blend_shape/model.inp 2>/dev/null || true

setup-fallback:
	mkdir -p assets/fallback
	gh release download v0.01 --repo sawarae/utsutsu-code --dir assets/fallback --pattern '*.png' --clobber
