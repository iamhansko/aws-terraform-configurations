"""Checks the execution input: a non-empty name string and a positive integer age.

The state machine's Choice state branches on the isValid this returns, so an input the check cannot handle
has to come back as isValid False rather than as an exception. The _monolithic version compared
data.get('age', 0) > 0 directly, so an age passed as a string ("25") or a null name raised a TypeError: the
task failed, the whole execution failed, and neither notification state ran - the input NotifyFailed exists
for never reached it.
"""


def lambda_handler(event, context):
    data = event.get('data') if isinstance(event, dict) else None
    if not isinstance(data, dict):
        data = {}

    name = data.get('name')
    age = data.get('age')
    # bool is a subclass of int in Python, so without the second check true would pass as age 1.
    is_valid = (
        isinstance(name, str) and len(name.strip()) > 0
        and isinstance(age, int) and not isinstance(age, bool) and age > 0
    )
    return {
        'statusCode': 200,
        'isValid': is_valid,
        'data': data,
        'message': 'Valid data' if is_valid else 'Invalid data'
    }
