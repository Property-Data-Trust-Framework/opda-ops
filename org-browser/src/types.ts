export interface ApiDiscoveryEndpoint {
  ApiDiscoveryId: string;
  ApiEndpoint: string;
}

export interface ApiResource {
  ApiResourceId: string;
  ApiVersion: string;
  ApiFamilyID: string;
  ApiFamilyType: string;
  CertificationStatus: string;
  FamilyComplete: boolean;
  Status: string;
  ApiDiscoveryEndpoints: ApiDiscoveryEndpoint[];
}

export interface AuthorisationServer {
  AuthorisationServerId: string;
  OrganisationId: string;
  CustomerFriendlyName: string;
  CustomerFriendlyDescription: string | null;
  CustomerFriendlyLogoUri: string | null;
  DeveloperPortalUri: string | null;
  TermsOfServiceUri: string | null;
  Status: string;
  ApiResources: ApiResource[];
}

export interface Participant {
  OrganisationId: string;
  OrganisationName: string;
  LegalEntityName: string;
  Status: string;
  CountryOfRegistration: string | null;
  City: string | null;
  Postcode: string | null;
  RegistrationNumber: string | null;
  CreatedOn: string;
  AuthorisationServers: AuthorisationServer[];
}
