# staging checkout runbook

- URL: `https://staging.example.test/checkout?fixture=failed-payment`
- Reproduction: submit a card, let the provider return a timeout, then retry
- Expected: the confirmation page appears after the retry succeeds
- Observed: the order remains `pending` and the page waits indefinitely
