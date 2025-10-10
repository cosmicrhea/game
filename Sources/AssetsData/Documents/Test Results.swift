extension Document {
  static let testResults = Document(
    id: "TEST_RESULTS",
    displayName: "Test Results",
    image: Image("Items/Documents/test_results.png"),

    pages: [
      """
      LAB REPORT — SAMPLE ID: █████-A12  
      Date: 03/14/2025  
      Collected at: Amager Pharma Research Wing
      """,

      """
      ### Blood Test Results:
      
      - Hematocrit: 44% (within normal range)  
      - Platelets: 218 ×10^9/L (normal)  
      - Crystalization Index: 0.07 (↑ abnormal)  
      - Reflective Surface Area (RSA): 1.3 cm² detected (unexpected)  
      """,

      """
      Notes: Subject reports mild dizziness.
      Microscopic exam confirms *silica-like inclusions* in red cell structure.  
      **Recommendation:** further observation.
      """,

      """
      # TRIAL DATA — PROJECT ████ GLASS  
      Date: 03/22/2025  

      Subjects: ████████ (redacted)  
      Dosage: Compound 19-B (“clear solution”)
      """,

      """
      ### Observed Effects:
      
      - 3/10 subjects: glassy dermal patches within 4h.  
      - 6/10 subjects: *violent neurological event* followed by mutation onset.  
      - 1/10 subjects: no symptoms (possible immunity marker?).  

      **Anomalous finding:** immune subject shared rare blood group **HH (Bombay phenotype)**.
      """,

//      """
//      # INTERNAL MEMO — HANDWRITTEN ON REPORT
//      > “Stop running the tests. It’s not ‘treatment’ — it’s **conversion**.  
//      > If anyone reads this: DO NOT DRINK THE CLEAR SOLUTION.  
//      > — J.”
//      """
    ]
  )
}
