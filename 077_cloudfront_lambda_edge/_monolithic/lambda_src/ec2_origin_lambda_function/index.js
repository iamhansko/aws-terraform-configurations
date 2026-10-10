exports.handler = (event, context, callback) => {
  console.log("event");
  console.log(JSON.stringify(event));

  console.log("context");
  console.log(JSON.stringify(context));

  const request = event.Records[0].cf.request;
  const headers = request.headers;

  console.log(`REQUEST : ${request.method} ${request.uri} FROM ${request.clientIp}`);

  callback(null, request);
};
