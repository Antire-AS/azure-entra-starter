const { app } = require("@azure/functions");

// Assigns SWA roles to authenticated users.
//
// Static Web Apps uses roles to control route access. This function is called
// by the platform after login (configured via "rolesSource" in
// staticwebapp.config.json) to determine what roles the user should have.
//
// By default, all authenticated users get the "chat-user" role.
// You can extend this to assign different roles based on group membership,
// email domain, or other claims from the user's identity.

app.http("getRoles", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "get-roles",
  handler: async (request) => {
    const header = request.headers.get("x-ms-client-principal");
    if (!header) {
      return { jsonBody: { roles: [] } };
    }

    // All authenticated users get the chat-user role.
    // Access control (who can sign in at all) is handled by Entra ID
    // via app_role_assignment_required on the service principal — see
    // terraform/static-web-app/groups.tf.
    const roles = ["chat-user"];

    return { jsonBody: { roles } };
  },
});
