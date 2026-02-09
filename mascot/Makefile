.PHONY: setup-models setup-fallback setup clean clean-build clean-signal clean-assets clean-hooks

setup: setup-models setup-fallback

setup-models:
	mkdir -p assets/models/blend_shape assets/models/parts
	cp -n config/examples/blend_shape.toml assets/models/blend_shape/emotions.toml 2>/dev/null || true
	cp -n config/examples/parts.toml assets/models/parts/emotions.toml 2>/dev/null || true
	gh release download v0.01 --repo sawarae/utsutsu2d --dir assets/models/blend_shape --pattern '*.inp' --clobber

setup-fallback:
	mkdir -p assets/fallback
	gh release download v0.01 --repo sawarae/utsutsu-code --dir assets/fallback --pattern '*.png' --clobber

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
	rm -f assets/models/parts/*.inp
	rm -f assets/fallback/*.png
	@echo "Removed downloaded assets (run 'make setup' to re-download)"

clean-hooks:
	rm -f ~/.claude/hooks/mascot_tts.py
	rm -f ~/.claude/hooks/tts_config.toml
	@echo "Removed global hooks (run /tsukuyomi-setup to re-create)"
