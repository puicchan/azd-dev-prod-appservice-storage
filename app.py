import os
from datetime import datetime
from flask import Flask, render_template, request, redirect, url_for, flash
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

app = Flask(__name__, template_folder='app/templates')
app.secret_key = os.urandom(24)  # Secret key for flash messages

# Get the Azure Storage account details from environment variables
AZURE_STORAGE_BLOB_ENDPOINT = os.environ.get('AZURE_STORAGE_BLOB_ENDPOINT')
CONTAINER_NAME = os.environ.get('AZURE_STORAGE_CONTAINER_NAME', 'files')

# Initialize the Azure Storage credentials and client
credential = DefaultAzureCredential()
blob_service_client = BlobServiceClient(account_url=AZURE_STORAGE_BLOB_ENDPOINT, credential=credential)

@app.route('/', methods=['GET'])
def index():
    """Render the home page with the upload form."""
    return render_template('index.html')

@app.route('/upload', methods=['POST'])
def upload_file():
    """Handle the file upload from the text area."""
    if request.method == 'POST':
        # Get the filename and content from the form
        filename = request.form.get('filename')
        file_content = request.form.get('file_content')
        
        if not filename or not file_content:
            flash('Both filename and content are required.', 'error')
            return redirect(url_for('index'))
        
        try:
            # Create the container if it doesn't exist
            container_client = blob_service_client.get_container_client(CONTAINER_NAME)
            if not container_client.exists():
                container_client.create_container()
            
            # Upload the content to Azure Blob Storage
            blob_client = container_client.get_blob_client(filename)
            blob_client.upload_blob(file_content, overwrite=True)
            
            flash(f'File {filename} uploaded successfully!', 'success')
        except Exception as e:
            flash(f'Error uploading file: {str(e)}', 'error')
        
        return redirect(url_for('index'))

@app.route('/files', methods=['GET'])
def list_files():
    """List all files in the Azure Storage container."""
    try:
        # Get the container client
        container_client = blob_service_client.get_container_client(CONTAINER_NAME)
        
        # List all blobs in the container
        blobs = container_client.list_blobs()
        files = [blob.name for blob in blobs]
        
        return render_template('files.html', files=files)
    except Exception as e:
        flash(f'Error listing files: {str(e)}', 'error')
        return redirect(url_for('index'))

@app.route('/files/<filename>', methods=['GET'])
def view_file(filename):
    """View the content of a file."""
    try:
        # Get the blob client
        container_client = blob_service_client.get_container_client(CONTAINER_NAME)
        blob_client = container_client.get_blob_client(filename)
        
        # Download the blob
        download_stream = blob_client.download_blob()
        file_content = download_stream.readall().decode('utf-8')
        
        return render_template('view.html', filename=filename, content=file_content)
    except Exception as e:
        flash(f'Error viewing file: {str(e)}', 'error')
        return redirect(url_for('files'))

@app.route('/health')
def health_check():
    """Health check endpoint for Front Door and load balancer probes."""
    try:
        # Test storage connectivity
        container_client = blob_service_client.get_container_client(CONTAINER_NAME)
        container_client.get_container_properties()
        
        # Return healthy response
        return {
            'status': 'healthy',
            'timestamp': datetime.utcnow().isoformat(),
            'services': {
                'storage': 'healthy',
                'application': 'healthy'
            }
        }, 200
    except Exception as e:
        # Return unhealthy response
        return {
            'status': 'unhealthy',
            'timestamp': datetime.utcnow().isoformat(),
            'error': str(e),
            'services': {
                'storage': 'unhealthy',
                'application': 'healthy'
            }
        }, 503

@app.route('/info')
def app_info():
    """Application info endpoint for monitoring and debugging."""
    import os
    import platform
    
    return {
        'application': 'Azure Multi-Region File App',
        'version': '1.0.0',
        'region': os.environ.get('AZURE_REGION', 'unknown'),
        'environment': os.environ.get('AZURE_ENV_NAME', 'unknown'),
        'hostname': platform.node(),
        'storage_endpoint': AZURE_STORAGE_BLOB_ENDPOINT,
        'container_name': CONTAINER_NAME
    }

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
