import { useEffect, useMemo, useState } from 'react';
import type { Participant } from './types';
import { collectApiFamilyTypes, fetchParticipants, orgHasFamilyType } from './api';
import { FilterBar } from './components/FilterBar';
import { OrgCard } from './components/OrgCard';

type LoadState =
  | { status: 'loading' }
  | { status: 'error'; error: string }
  | { status: 'ready'; data: Participant[] };

const ALL = 'all';

export function App() {
  const [load, setLoad] = useState<LoadState>({ status: 'loading' });
  const [familyType, setFamilyType] = useState<string>(ALL);

  useEffect(() => {
    fetchParticipants()
      .then((data) => setLoad({ status: 'ready', data }))
      .catch((err: unknown) =>
        setLoad({ status: 'error', error: err instanceof Error ? err.message : String(err) }),
      );
  }, []);

  const familyTypes = useMemo(
    () => (load.status === 'ready' ? collectApiFamilyTypes(load.data) : []),
    [load],
  );

  const visible = useMemo(() => {
    if (load.status !== 'ready') return [];
    if (familyType === ALL) return load.data;
    return load.data.filter((org) => orgHasFamilyType(org, familyType));
  }, [load, familyType]);

  return (
    <div className="app">
      <header className="app-header">
        <h1>OPDA Org Browser</h1>
        <p className="subtitle">Participants in the OPDA directory at Raidiam.</p>
      </header>

      {load.status === 'loading' && <p className="status">Loading…</p>}

      {load.status === 'error' && (
        <p className="status status-error">Failed to load: {load.error}</p>
      )}

      {load.status === 'ready' && (
        <>
          <FilterBar
            options={familyTypes}
            value={familyType}
            onChange={setFamilyType}
            allValue={ALL}
            totalCount={load.data.length}
            visibleCount={visible.length}
          />
          <ul className="org-list">
            {visible.map((org) => (
              <OrgCard key={org.OrganisationId} org={org} />
            ))}
          </ul>
        </>
      )}
    </div>
  );
}
