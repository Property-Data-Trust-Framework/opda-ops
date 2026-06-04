import { ApiReferenceReact } from '@scalar/api-reference-react';
import '@scalar/api-reference-react/style.css';

const sources = [
  {
    url: '/specs/opda-lr-facade.yaml',
    title: 'HMLR Facade (Go)',
    slug: 'lr-facade',
  },
  {
    url: '/specs/opda-uprn-validator.yaml',
    title: 'UPRN Validator (.NET)',
    slug: 'uprn-validator',
  },
  {
    url: '/specs/opda-mra-api.yaml',
    title: 'Mining Remediation (.NET)',
    slug: 'mra-api',
  },
  {
    url: '/specs/opda-os-api.yaml',
    title: 'Ordnance Survey (.NET)',
    slug: 'os-api',
  },
  {
    url: '/specs/opda-council-tax-api.yaml',
    title: 'Council Tax Band (.NET)',
    slug: 'council-tax-api',
  },
  {
    url: '/specs/opda-epc-api.yaml',
    title: 'Energy Performance Certificate (.NET)',
    slug: 'epc-api',
  },
  {
    url: '/specs/opda-survey-shack-api.yaml',
    title: 'Survey Shack (.NET)',
    slug: 'survey-shack-api',
  },
  {
    url: '/specs/opda-armalytix-api.yaml',
    title: 'Armalytix Proof of Funds (.NET)',
    slug: 'armalytix-api',
  },
  {
    url: '/specs/opda-smoove-api.yaml',
    title: 'Smoove Conveyancing Events (.NET)',
    slug: 'smoove-api',
  },
];

export function App() {
  return (
    <ApiReferenceReact
      configuration={{
        sources,
        hideClientButton: false,
      }}
    />
  );
}
