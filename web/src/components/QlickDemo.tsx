import { useCallback, useMemo, useState } from 'react'

const RPC = 'https://sepolia.unichain.org'

// Deployed addresses from docs/Qlick-Unichain-Sepolia.md
const QM_ADDRESS = '0x6CD1EfcA0D1DF8BB55c45fEF2D1F4962103B00F7'
const ORCH_ADDRESS = '0x641eCbB155b8589120005dE67e7aBF524034EA5B'
const STATEVIEW_ADDRESS = '0xC199F1072A74D4E905aBa1a84d9A45E2546b6222'
const POOL_A = '0x9c3d5240b4029c50dca2ac63aa82ec256e1741c637d22ac61856ff9c9ea37fc1'
const POOL_B = '0xed9ff8b0b533acb50aa685c8b165023513a597e63d67175e0219da4e3a8b206b'

async function jsonRpc<T>(method: string, params: any[]): Promise<T> {
  const res = await fetch(RPC, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  })
  const data = await res.json()
  if (data.error) throw new Error(data.error.message)
  return data.result
}

async function callGetSlot0(poolIdHex: string) {
  // function getSlot0(bytes32)(uint160,int24,uint24,uint24)
  const selector = '0xc8f5b8ab' // keccak256("getSlot0(bytes32)") first 4 bytes
  const paddedPoolId = poolIdHex.replace(/^0x/, '').padStart(64, '0')
  const data = `0x${selector}${paddedPoolId}`
  const result: string = await jsonRpc('eth_call', [{ to: STATEVIEW_ADDRESS, data }, 'latest'])
  // Decode: uint160 (32b), int24 (as int256), uint24, uint24 — all 32-byte padded
  const hex = result.replace(/^0x/, '')
  const sqrtPriceX96 = BigInt('0x' + hex.slice(0, 64))
  const tickRaw = BigInt('0x' + hex.slice(64, 128))
  const protocolFee = parseInt(hex.slice(128, 192), 16)
  const lpFee = parseInt(hex.slice(192, 256), 16)
  // int24 sign fix (take lower 24 bits)
  const t24 = Number(tickRaw & BigInt(0xffffff))
  const tick = t24 & 0x800000 ? t24 - 0x1000000 : t24
  return { sqrtPriceX96, tick, protocolFee, lpFee }
}

export default function QlickDemo() {
  const [poolA, setPoolA] = useState<{ sqrtPriceX96: bigint; tick: number } | null>(null)
  const [poolB, setPoolB] = useState<{ sqrtPriceX96: bigint; tick: number } | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    try {
      setError(null)
      setLoading(true)
      const [a, b] = await Promise.all([callGetSlot0(POOL_A), callGetSlot0(POOL_B)])
      setPoolA({ sqrtPriceX96: a.sqrtPriceX96, tick: a.tick })
      setPoolB({ sqrtPriceX96: b.sqrtPriceX96, tick: b.tick })
    } catch (e: any) {
      setError(e.message ?? 'Failed to fetch')
    } finally {
      setLoading(false)
    }
  }, [])

  const priceNote = useMemo(() => {
    if (!poolA) return ''
    return `Pool A tick: ${poolA.tick}`
  }, [poolA])

  return (
    <div style={{ padding: 16, display: 'grid', gap: 12 }}>
      <h2>Qlick Demo (Unichain Sepolia)</h2>
      <div style={{ display: 'grid', gap: 8 }}>
        <div>QuantumMarketManager: {QM_ADDRESS}</div>
        <div>Orchestrator: {ORCH_ADDRESS}</div>
      </div>
      <div style={{ display: 'flex', gap: 12 }}>
        <button disabled={loading} onClick={refresh}>Refresh Prices</button>
        {loading && <span>Loading…</span>}
        {error && <span style={{ color: 'crimson' }}>{error}</span>}
      </div>
      <div style={{ display: 'grid', gap: 8 }}>
        <div>
          <strong>Pool A</strong>
          <div>poolId: {POOL_A}</div>
          <div>tick: {poolA?.tick ?? '-'}</div>
          <div>sqrtPriceX96: {poolA?.sqrtPriceX96?.toString() ?? '-'}</div>
        </div>
        <div>
          <strong>Pool B</strong>
          <div>poolId: {POOL_B}</div>
          <div>tick: {poolB?.tick ?? '-'}</div>
          <div>sqrtPriceX96: {poolB?.sqrtPriceX96?.toString() ?? '-'}</div>
        </div>
      </div>
      <small>{priceNote}</small>
    </div>
  )
}


