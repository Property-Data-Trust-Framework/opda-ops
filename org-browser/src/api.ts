import type { Participant } from './types';

const ENDPOINT = 'https://data.directory.pdtf.raidiam.io/participants';

export async function fetchParticipants(): Promise<Participant[]> {
  const response = await fetch(ENDPOINT);
  if (!response.ok) {
    throw new Error(`Directory returned ${response.status} ${response.statusText}`);
  }
  return (await response.json()) as Participant[];
}

export function collectApiFamilyTypes(participants: Participant[]): string[] {
  const types = new Set<string>();
  for (const org of participants) {
    for (const server of org.AuthorisationServers) {
      for (const resource of server.ApiResources) {
        if (resource.ApiFamilyType) types.add(resource.ApiFamilyType);
      }
    }
  }
  return Array.from(types).sort();
}

export function orgHasFamilyType(org: Participant, familyType: string): boolean {
  return org.AuthorisationServers.some((server) =>
    server.ApiResources.some((resource) => resource.ApiFamilyType === familyType),
  );
}
