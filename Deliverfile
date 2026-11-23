app_identifier("com.coteditor.CotEditor")
platform("osx")

metadata_path("./metadata")
screenshots_path("./screenshots")
# all languages on the store, including those without localized metadata
languages(Dir.glob("./screenshots/*/").map { |path| File.basename(path) })

skip_binary_upload(true)
skip_app_version_update(true)
submit_for_review(false)
run_precheck_before_submit(false)
overwrite_screenshots(true)
force(true)  # skip HTML preview
