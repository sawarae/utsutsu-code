.PHONY: setup-models setup-fallback

setup-models:
	mkdir -p assets/models/blend_shape assets/models/parts
	cp config/examples/blend_shape.toml assets/models/blend_shape/emotions.toml
	cp config/examples/parts.toml assets/models/parts/emotions.toml
	@echo "Place model.inp files in each directory under assets/models/"

setup-fallback:
	mkdir -p assets/fallback
	gh release download v0.01 --repo sawarae/utsutsu-code --dir assets/fallback --pattern '*.png'
