# EarningsCallBiz

Ruby client for the EarningsCall.biz API.

The official SDKs use `https://v2.api.earningscall.biz` with an `apikey` query parameter. This gem reads API keys in this order:

1. `EARNINGSCALLBIZ_API_KEY`
2. `EARNINGSCALL_API_KEY`
3. `ECALL_API_KEY`
4. `demo`

## Usage

```ruby
api = EarningsCallBiz::API.new

api.calendar(Date.today)
api.events(exchange: "NASDAQ", symbol: "AAPL")
api.transcript(exchange: "NASDAQ", symbol: "AAPL", year: 2026, quarter: 1, level: 4)
api.download_audio_file(exchange: "NASDAQ", symbol: "AAPL", year: 2026, quarter: 1)
api.download_slide_deck(exchange: "NASDAQ", symbol: "AAPL", year: 2026, quarter: 1)
```

Transcript levels follow the official SDK behavior:

- `1`: basic transcript
- `2`: speaker transcript
- `3`: word-level transcript
- `4`: prepared remarks and Q&A sections
