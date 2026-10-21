import XCTest
@testable import StrandImport

final class LabFhirImportTests: XCTestCase {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testBundleOfObservations() {
        let json = """
        {"resourceType":"Bundle","entry":[
         {"resource":{"resourceType":"Observation","status":"final","code":{"coding":[{"system":"http://loinc.org","code":"13457-7","display":"LDL"}],"text":"LDL Cholesterol"},
          "effectiveDateTime":"2026-10-07T08:30:00+07:00","valueQuantity":{"value":3.1,"unit":"mmol/L"},
          "referenceRange":[{"high":{"value":3.4}}]}},
         {"resource":{"resourceType":"Observation","status":"final","code":{"text":"Ferritin"},"effectiveDateTime":"2026-10-07",
          "valueQuantity":{"value":58,"unit":"ug/L"},"referenceRange":[{"low":{"value":30},"high":{"value":300}}]}},
         {"resource":{"resourceType":"Patient","id":"x"}}
        ]}
        """
        XCTAssertTrue(LabFhirImport.matches(data: data(json)))
        let r = LabFhirImport.parse(data: data(json))
        XCTAssertEqual(r.rows.count, 2)
        let ldl = r.rows.first { $0.markerKey == "ldl" }
        XCTAssertEqual(ldl?.value, 3.1); XCTAssertEqual(ldl?.unit, "mmol/L"); XCTAssertEqual(ldl?.day, "2026-10-07"); XCTAssertEqual(ldl?.referenceText, "<3.4")
        let fer = r.rows.first { $0.markerKey == "ferritin" }
        XCTAssertEqual(fer?.referenceText, "30 - 300"); XCTAssertEqual(fer?.unit, "ug/L")
        XCTAssertEqual(r.skippedRows, 0)
    }

    func testBloodPressurePanelBecomesThePair() {
        let json = """
        {"resourceType":"Observation","status":"final","code":{"coding":[{"system":"http://loinc.org","code":"85354-9"}]},"effectiveDateTime":"2026-10-07",
         "component":[
          {"code":{"coding":[{"system":"http://loinc.org","code":"8480-6"}]},"valueQuantity":{"value":118,"unit":"mmHg"}},
          {"code":{"coding":[{"system":"http://loinc.org","code":"8462-4"}]},"valueQuantity":{"value":78,"unit":"mmHg"}}]}
        """
        let r = LabFhirImport.parse(data: data(json))
        XCTAssertEqual(r.rows.map(\.markerKey).sorted(), ["bp_diastolic", "bp_systolic"])
        XCTAssertEqual(r.rows.first { $0.markerKey == "bp_systolic" }?.value, 118)
    }

    func testUnreadableObservationsAreSkippedAndCounted() {
        let json = """
        [{"resourceType":"Observation","code":{"text":"Colour"},"effectiveDateTime":"2026-10-07","valueString":"yellow"},
         {"resourceType":"Observation","code":{"text":"Glucose"},"valueQuantity":{"value":5.0,"unit":"mmol/L"}},
         {"resourceType":"Observation","status":"entered-in-error","code":{"text":"Glucose"},"effectiveDateTime":"2026-10-07","valueQuantity":{"value":5.0}}]
        """
        let r = LabFhirImport.parse(data: data(json))
        XCTAssertTrue(r.rows.isEmpty)
        XCTAssertEqual(r.skippedRows, 3)
    }

    func testNotFhirIsNotMatched() {
        XCTAssertFalse(LabFhirImport.matches(data: data("{\"a\":1}")))
        XCTAssertFalse(LabFhirImport.matches(data: data("date,marker,value")))
    }
}
