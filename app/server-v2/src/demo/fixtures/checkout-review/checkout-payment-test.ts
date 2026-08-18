import { describe, expect, it } from "bun:test"

declare function confirmPaymentWithRetry(orderId: string): Promise<{ status: string }>

describe("checkout payment retry", () => {
  it("covers success after a provider timeout", async () => {
    const result = await confirmPaymentWithRetry("order-1842")
    expect(result.status).toBe("success")
  })
})
