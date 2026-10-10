"""Turns a validated record into its processed form.

Only reached on the Choice state's valid branch, so name is a non-empty string and age a positive integer
by the time this runs - the validate function guarantees both.
"""

from datetime import datetime, timezone


def lambda_handler(event, context):
    data = event.get('data', {})
    processed_data = {
        'id': f"user_{data.get('name', '').lower()}",
        'name': data.get('name', '').title(),
        'age': data.get('age', 0),
        'category': 'adult' if data.get('age', 0) >= 18 else 'minor',
        # The time this ran. The _monolithic version returned the literal '2024-01-01T00:00:00Z' for every
        # record, so every execution's output claimed the same moment.
        'processed_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    }
    return {
        'statusCode': 200,
        'processedData': processed_data
    }
