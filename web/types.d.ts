export interface Provider {
  request(args: { method: string; params?: unknown[] }): Promise<any>;
  on?(event: string, callback: (...args: any[]) => void): unknown;
  removeListener?(event: string, callback: (...args: any[]) => void): unknown;
  disconnect?(): Promise<void>;
}
export interface AppState {
  acct: string | null;
  chainOk: boolean;
  view: string | null;
  sel: Set<string>;
  inv: { id: number; lv: number; power: bigint; custody: string; free: boolean }[];
  pos: { ids: bigint[]; power: bigint; debt: bigint; line: bigint; thr: bigint } | null;
  vault: Partial<Record<'assets' | 'supply' | 'idle' | 'borrows' | 'unsettled' | 'power' | 'rate' | 'px' | 'claimable', bigint>>;
  valuer: Partial<Record<'price' | 'ltv' | 'lastChange', bigint>>;
  lend: { shares?: bigint; sqk?: bigint; allow?: bigint; approvedAll?: boolean };
  art: string | null;
  seed: string | null;
  renderer: string | null;
  apr: number;
  gen: number;
  dur: number;
  observedAt: number;
  rpm: number;
}
declare global {
  interface Window {
    ethereum?: Provider;
    __rpm?: number;
  }
}
