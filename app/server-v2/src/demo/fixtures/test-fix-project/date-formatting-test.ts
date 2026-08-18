import { describe, expect, it } from "bun:test"

declare function formatInvoiceDate(value: string): string

describe("formatInvoiceDate", () => {
  it("keeps the invoice date in UTC", () => {
    expect(formatInvoiceDate("2026-08-14T00:30:00Z")).toBe("Aug 14, 2026")
  })
})
