# A page with Apollo's embedded GraphQL sandbox, for trying operations in the browser.
# Development only: the route exists only when Rails.env.development? (see config/routes.rb).
class SandboxController < ApplicationController
  def show
    render html: <<~HTML.html_safe
      <!DOCTYPE html>
      <html>
        <body style="margin:0;height:100vh">
          <div id="sandbox" style="width:100%;height:100%"></div>
          <script src="https://embeddable-sandbox.cdn.apollographql.com/_latest/embeddable-sandbox.umd.production.min.js"></script>
          <script>
            new window.EmbeddedSandbox({
              target: "#sandbox",
              initialEndpoint: window.location.origin + "/graphql"
            });
          </script>
        </body>
      </html>
    HTML
  end
end
