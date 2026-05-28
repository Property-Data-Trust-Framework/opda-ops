import type { Participant } from '../types';

interface OrgCardProps {
  org: Participant;
}

export function OrgCard({ org }: OrgCardProps) {
  const location = [org.City, org.CountryOfRegistration].filter(Boolean).join(', ');
  const families = new Set<string>();
  for (const server of org.AuthorisationServers) {
    for (const resource of server.ApiResources) {
      if (resource.ApiFamilyType) families.add(resource.ApiFamilyType);
    }
  }

  return (
    <li className="org-card">
      <div className="org-card-head">
        <h2>{org.OrganisationName}</h2>
        <span className={`status-badge status-${org.Status.toLowerCase()}`}>{org.Status}</span>
      </div>
      {org.LegalEntityName && org.LegalEntityName !== org.OrganisationName && (
        <p className="legal-name">{org.LegalEntityName}</p>
      )}
      {location && <p className="meta">{location}</p>}

      <dl className="org-detail">
        <dt>Authorisation servers</dt>
        <dd>{org.AuthorisationServers.length}</dd>

        <dt>API families</dt>
        <dd>
          {families.size === 0 ? (
            <em className="muted">none registered</em>
          ) : (
            <ul className="family-tags">
              {Array.from(families)
                .sort()
                .map((family) => (
                  <li key={family} className="family-tag">
                    {family}
                  </li>
                ))}
            </ul>
          )}
        </dd>
      </dl>
    </li>
  );
}
