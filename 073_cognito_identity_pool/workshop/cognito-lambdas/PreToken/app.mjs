export const lambdaHandler = function(event, context) {

  // Processing user group info
  const userGroup = event.request.groupConfiguration.groupsToOverride;

  //Adding group to access token scopes
  event.response = {
    "claimsAndScopeOverrideDetails": {
      "idTokenGeneration": {},
      "accessTokenGeneration": {
        "claimsToAddOrOverride": {
        },
        "scopesToAdd": userGroup
      }
    }
  };

  // Return to Amazon Cognito
  context.done(null, event);
};
