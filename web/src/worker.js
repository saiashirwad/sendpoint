// Static site plus one download route. GitHub resolves this stable URL to the
// asset attached to the newest non-prerelease release, so downloads do not
// depend on a GitHub API request succeeding at click time.

const REPO = "saiashirwad/sendpoint";
const DOWNLOAD_URL = `https://github.com/${REPO}/releases/latest/download/Sendpoint.zip`;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === "/download" || url.pathname === "/download/") {
      return Response.redirect(DOWNLOAD_URL, 302);
    }
    return env.ASSETS.fetch(request);
  },
};
