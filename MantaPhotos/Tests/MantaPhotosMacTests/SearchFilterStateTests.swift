import Testing
@testable import MantaPhotosCore

@Suite
struct SearchFilterStateTests {
    @Test
    func sqlSelectionDefaultsExcludeTrashAndHidden() {
        let selection = SearchFilterState().makeSQLSelection()

        #expect(selection.whereClause.contains("photo_assets.is_hidden = 0"))
        #expect(selection.whereClause.contains("photo_assets.in_trash = ?"))
        #expect(selection.arguments == [.int(0)])
    }

    @Test
    func sqlSelectionSupportsScoreAndMediaTypeFilters() {
        var state = SearchFilterState()
        state.mediaTypes = [.image, .video]
        state.minimumAestheticScore = 80

        let selection = state.makeSQLSelection()

        #expect(selection.whereClause.contains("photo_assets.media_type in (?, ?)"))
        #expect(selection.whereClause.contains("photo_scores.aesthetic_score >= ?"))
        #expect(selection.arguments.contains(.text("image")))
        #expect(selection.arguments.contains(.text("video")))
        #expect(selection.arguments.contains(.double(80)))
    }

    @Test
    func sqlSelectionSupportsScreenshotAndDeviceFilters() {
        var state = SearchFilterState()
        state.screenshotsOnly = true
        state.deviceCategories = [.phone, .screenshot]

        let selection = state.makeSQLSelection()

        #expect(selection.whereClause.contains("(photo_assets.media_subtypes_raw & ?) != 0"))
        #expect(selection.whereClause.contains("photo_assets.device_category in (?, ?)"))
        #expect(selection.arguments.contains(.text("phone")))
        #expect(selection.arguments.contains(.text("screenshot")))
    }

    @Test
    func sqlSelectionSupportsLowToHighScoreSorting() {
        var state = SearchFilterState()
        state.sortMode = .aestheticScoreAscending

        let selection = state.makeSQLSelection()

        #expect(selection.orderBy == "photo_scores.aesthetic_score asc nulls last, photo_assets.creation_date desc nulls last")
    }
}
