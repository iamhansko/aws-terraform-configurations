import express from "express";
import authn from "./authn/app.js";
const app = express();
const port = process.env["PORT"] || 8080;
app.use(express.json());
app.use(express.static("public"));
app.use((req, res, next) => {
  if (req.get("x-forwarded-proto") &&
      (req.get("x-forwarded-proto")).split(",")[0] !== "https") {
    return res.redirect(301, "https://" + req.get("host"));
  }
  req.schema = "https";
  next();
});
app.get("/", (req, res) => {
  res.send("Amazon Cognito Workshop");
});
app.get("/callback", (req, res) => {
  res.type("html");
  res.status(200);
  res.send(`
    <!DOCTYPE html><html><body onload="zFunc()"><script>
    function zFunc() { if (window.location.hash.length > 0) window.location.replace(window.location.href.replace("#", "?")); }
    </script><pre style="background-color:#C0C0C0;padding:1em;white-space:pre-wrap;overflow-wrap:break-word"><code>` + JSON.stringify(req.query, null, 2) + `</code></pre></body></html>
  `);
});
app.use("/authn", authn);
app.listen(port);
