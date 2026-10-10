import boto3
import json
import cfnresponse
import logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)
def is_valid_json(json_string):
  logger.debug(f'Calling is_valid_json: {json_string}')
  try:
    json.loads(json_string)
    logger.info('Secret is in json format')
    return True
  except json.JSONDecodeError:
    logger.info('Secret is in string format')
    return False
def lambda_handler(event, context):
  logger.debug(f'event: {event}')
  logger.debug(f'context: {context}')
  try:
    if event['RequestType'] == 'Delete':
      cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData={}, reason='No action to take')
    else:
      resource_properties = event['ResourceProperties']
      secret_name = resource_properties['SecretArn']
      secrets_mgr = boto3.client('secretsmanager')
      logger.info(f'Getting secret from {secret_name}')
      secret = secrets_mgr.get_secret_value(SecretId=secret_name)
      logger.debug(f'secret: {secret}')
      secret_value = secret['SecretString']
      responseData = {}
      if is_valid_json(secret_value):
          secret_json = json.loads(secret_value)
          responseData = secret_json
      else:
          responseData = {'secret': secret_value}
      logger.debug(f'responseData: {responseData}')
      logger.debug(f'type(responseData): {type(responseData)}')
      cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData=responseData, reason='OK', noEcho=True)
  except Exception as e:
    logger.error(e)
    cfnresponse.send(event, context, cfnresponse.FAILED, responseData={}, reason=str(e))
