const POOL_DATA = {
  UserPoolId: "${WS_USER_POOL_ID}",
  IdentityPoolId: "${WS_IDENTITY_POOL_ID}",
  ClientId: "${WS_USER_POOL_CLIENT_ID}",
  Region: "${WS_REGION}",
  ServiceEndpoint: "https://${WS_MOCK_API_ID}.execute-api.${WS_REGION}.amazonaws.com/Prod/pets"
};
export { POOL_DATA }
