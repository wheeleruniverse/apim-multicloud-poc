"""
Hello API - Multi-Cloud Proof of Concept
A simple API that returns a greeting with cloud provider information.
"""

import os
import socket
from datetime import datetime, timezone
from flask import Flask, jsonify, request
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration from environment variables
CLOUD_PROVIDER = os.environ.get('CLOUD_PROVIDER', 'Unknown')
REGION = os.environ.get('REGION', 'Unknown')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'Unknown')
POD_NAME = os.environ.get('POD_NAME', socket.gethostname())
POD_IP = os.environ.get('POD_IP', 'Unknown')


def get_request_info():
    """Extract useful information from the incoming request."""
    return {
        'client_ip': request.remote_addr,
        'forwarded_for': request.headers.get('X-Forwarded-For'),
        'apim_gateway': request.headers.get('X-APIM-Gateway'),
        'user_agent': request.headers.get('User-Agent'),
    }


@app.route('/hello', methods=['GET'])
def hello():
    """
    Main hello endpoint.
    Returns a greeting with cloud provider and instance information.
    """
    request_info = get_request_info()
    
    response = {
        'message': f'Hello from {CLOUD_PROVIDER}!',
        'source': CLOUD_PROVIDER,
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'instance': {
            'cloud': CLOUD_PROVIDER,
            'region': REGION,
            'environment': ENVIRONMENT,
            'pod_name': POD_NAME,
            'pod_ip': POD_IP,
        },
        'request': {
            'client_ip': request_info['client_ip'],
            'forwarded_for': request_info['forwarded_for'],
            'gateway': request_info['apim_gateway'],
        }
    }
    
    logger.info(f"Hello request served - Cloud: {CLOUD_PROVIDER}, Gateway: {request_info['apim_gateway']}")
    
    return jsonify(response)


@app.route('/health', methods=['GET'])
def health():
    """
    Health check endpoint for Kubernetes probes.
    """
    return jsonify({
        'status': 'healthy',
        'cloud': CLOUD_PROVIDER,
        'timestamp': datetime.now(timezone.utc).isoformat(),
    })


@app.route('/ready', methods=['GET'])
def ready():
    """
    Readiness check endpoint for Kubernetes probes.
    """
    return jsonify({
        'status': 'ready',
        'cloud': CLOUD_PROVIDER,
        'timestamp': datetime.now(timezone.utc).isoformat(),
    })


@app.route('/info', methods=['GET'])
def info():
    """
    Detailed information endpoint for debugging.
    """
    return jsonify({
        'service': 'hello-api',
        'version': '1.0.0',
        'cloud_provider': CLOUD_PROVIDER,
        'region': REGION,
        'environment': ENVIRONMENT,
        'instance': {
            'pod_name': POD_NAME,
            'pod_ip': POD_IP,
            'hostname': socket.gethostname(),
        },
        'timestamp': datetime.now(timezone.utc).isoformat(),
    })


@app.route('/simulate/slow', methods=['GET'])
def simulate_slow():
    """
    Simulate a slow response for testing timeout configurations.
    Query parameter: delay (seconds, default 5)
    """
    import time
    delay = request.args.get('delay', 5, type=int)
    delay = min(delay, 30)  # Cap at 30 seconds
    
    time.sleep(delay)
    
    return jsonify({
        'message': f'Slow response after {delay} seconds',
        'delay_seconds': delay,
        'cloud': CLOUD_PROVIDER,
        'timestamp': datetime.now(timezone.utc).isoformat(),
    })


@app.route('/simulate/error', methods=['GET'])
def simulate_error():
    """
    Simulate various error responses for testing error handling.
    Query parameter: code (HTTP status code, default 500)
    """
    code = request.args.get('code', 500, type=int)
    
    error_messages = {
        400: 'Bad Request - Simulated client error',
        401: 'Unauthorized - Simulated authentication failure',
        403: 'Forbidden - Simulated authorization failure',
        404: 'Not Found - Simulated missing resource',
        429: 'Too Many Requests - Simulated rate limit',
        500: 'Internal Server Error - Simulated server error',
        502: 'Bad Gateway - Simulated upstream error',
        503: 'Service Unavailable - Simulated service failure',
        504: 'Gateway Timeout - Simulated timeout',
    }
    
    message = error_messages.get(code, f'Simulated error with code {code}')
    
    return jsonify({
        'error': message,
        'code': code,
        'cloud': CLOUD_PROVIDER,
        'timestamp': datetime.now(timezone.utc).isoformat(),
    }), code


@app.errorhandler(404)
def not_found(error):
    return jsonify({
        'error': 'Endpoint not found',
        'cloud': CLOUD_PROVIDER,
        'timestamp': datetime.now(timezone.utc).isoformat(),
    }), 404


@app.errorhandler(500)
def internal_error(error):
    return jsonify({
        'error': 'Internal server error',
        'cloud': CLOUD_PROVIDER,
        'timestamp': datetime.now(timezone.utc).isoformat(),
    }), 500


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    debug = os.environ.get('DEBUG', 'false').lower() == 'true'
    
    logger.info(f"Starting Hello API on port {port}")
    logger.info(f"Cloud Provider: {CLOUD_PROVIDER}")
    logger.info(f"Region: {REGION}")
    logger.info(f"Environment: {ENVIRONMENT}")
    
    app.run(host='0.0.0.0', port=port, debug=debug)
