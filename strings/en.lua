-- English UI text. Keys are shared with strings/fi.lua (tests/strings_test.lua checks parity).
-- err.<code>.what says what happened, err.<code>.action suggests the one next step.
return {
  err = {
    missing_marker = { what = "This pack is not complete yet.", action = "Wait a moment for the files to finish arriving, then try again." },
    bad_manifest = { what = "The pack's file list is damaged.", action = "Ask for the pack to be sent again." },
    marker_mismatch = { what = "The pack was changed after it was finished.", action = "Ask for the pack to be sent again." },
    missing_file = { what = "The file {path} is missing.", action = "Wait for the files to finish arriving, or ask for the pack to be sent again." },
    size_mismatch = { what = "The file {path} is incomplete.", action = "Wait for the file to finish arriving, then try again." },
    hash_mismatch = { what = "The file {path} is damaged.", action = "Ask for the pack to be sent again." },
    unreadable_file = { what = "The file {path} could not be read.", action = "Check that the file is kept on this computer and try again." },
    band_unreadable = { what = "The band settings could not be found.", action = "Check that you chose the right band folder." },
    band_invalid = { what = "The band settings file has a problem ({detail}).", action = "Ask the producer to fix the band settings." },
    band_too_new = { what = "The band settings were made with a newer version of this tool.", action = "Update the tool and try again." },
  },
}
