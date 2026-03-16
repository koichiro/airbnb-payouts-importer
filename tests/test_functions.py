import pytest
import pandas as pd
import logging
from unittest.mock import MagicMock, patch
from google.cloud.exceptions import NotFound
from decimal import Decimal

# The function to be tested
from src.functions import load_airbnb_csv

# --- Test Fixtures ---

@pytest.fixture
def mock_gcs_blob():
    """Fixture for a mock GCS blob object."""
    blob = MagicMock()
    blob.download_as_bytes.return_value = b"" # Default empty content
    return blob

@pytest.fixture
def mock_storage_client(mock_gcs_blob):
    """Fixture for a mock GCS client that returns a mock blob."""
    client = MagicMock()
    bucket = MagicMock()
    bucket.blob.return_value = mock_gcs_blob
    client.bucket.return_value = bucket
    return client

@pytest.fixture
def mock_bigquery_client():
    """Fixture for a mock BigQuery client."""
    client = MagicMock()
    # Mock the job result
    job = MagicMock()
    job.result.return_value = None
    client.load_table_from_dataframe.return_value = job
    
    # Mock for MERGE query
    query_job = MagicMock()
    query_job.result.return_value = None
    query_job.dml_stats.inserted_row_count = 1
    query_job.dml_stats.updated_row_count = 0
    client.query.return_value = query_job

    return client

def create_mock_event(data_dict):
    """Helper to create a mock event object with a .data attribute (Gen 2 style)."""
    event = MagicMock()
    event.data = data_dict
    return event

# --- Test Cases ---

@patch('src.functions.storage.Client')
@patch('src.functions.bigquery.Client')
def test_successful_run_first_time(mock_bq_client_cls, mock_storage_client_cls, mock_gcs_blob, mock_storage_client, mock_bigquery_client):
    """
    Tests a successful first-time run where the target table does not exist.
    """
    # --- Arrange ---
    mock_storage_client_cls.return_value = mock_storage_client
    mock_bq_client_cls.return_value = mock_bigquery_client
    
    # Use helper to create Gen 2 style event
    event = create_mock_event({"bucket": "test-bucket", "name": "test-file.csv"})
    
    csv_content = b"""\
"\xe6\x97\xa5\xe4\xbb\x98","\xe7\xa8\xae\xe5\x88\xa5","\xe6\xb3\x8a\xe6\x95\xb0","\xe9\x87\x91\xe9\xa1\x8d"
"10/15/2025","Reservation","2","150.50"
"""
    mock_gcs_blob.download_as_bytes.return_value = csv_content

    # Simulate target table not found
    mock_bigquery_client.get_table.side_effect = NotFound("Table not found")
    
    # --- Act ---
    load_airbnb_csv(event, None)

    # --- Assert ---
    mock_bigquery_client.load_table_from_dataframe.assert_called_once()
    mock_bigquery_client.get_table.assert_called_once()
    mock_bigquery_client.copy_table.assert_called_once()
    mock_bigquery_client.query.assert_not_called()

    loaded_df = mock_bigquery_client.load_table_from_dataframe.call_args[0][0]
    assert "event_date" in loaded_df.columns
    assert loaded_df["amount"][0] == Decimal("150.5")
    assert loaded_df["number_of_nights"][0] == 2

@patch('src.functions.storage.Client')
@patch('src.functions.bigquery.Client')
def test_successful_run_merge(mock_bq_client_cls, mock_storage_client_cls, mock_gcs_blob, mock_storage_client, mock_bigquery_client):
    """
    Tests a successful subsequent run where the target table exists and a MERGE is performed.
    """
    # --- Arrange ---
    mock_storage_client_cls.return_value = mock_storage_client
    mock_bq_client_cls.return_value = mock_bigquery_client
    
    event = create_mock_event({"bucket": "test-bucket", "name": "test-file.csv"})
    
    csv_content = b"""\
"\xe6\x97\xa5\xe4\xbb\x98","\xe7\xa8\xae\xe5\x88\xa5","\xe9\x87\x91\xe9\xa1\x8d"
"10/16/2025","Payout","200.00"
"""
    mock_gcs_blob.download_as_bytes.return_value = csv_content

    # Simulate target table being found
    mock_bigquery_client.get_table.return_value = MagicMock()
    
    # --- Act ---
    load_airbnb_csv(event, None)

    # --- Assert ---
    mock_bigquery_client.copy_table.assert_not_called()
    mock_bigquery_client.query.assert_called_once()
    merge_sql = mock_bigquery_client.query.call_args[0][0]
    assert "MERGE" in merge_sql

@patch('src.functions.storage.Client')
@patch('src.functions.bigquery.Client')
def test_skip_non_csv_file(mock_bq_client_cls, mock_storage_client_cls):
    """
    Tests that the function exits early if the file is not a CSV.
    """
    # --- Arrange ---
    mock_storage_client_cls.return_value = MagicMock()
    mock_bq_client_cls.return_value = MagicMock()
    
    event = create_mock_event({"bucket": "test-bucket", "name": "test-file.txt"})
    
    # --- Act ---
    result = load_airbnb_csv(event, None)

    # --- Assert ---
    assert result is None 
    mock_storage_client_cls.return_value.bucket.assert_not_called()

@patch('src.functions.storage.Client')
@patch('src.functions.bigquery.Client')
def test_missing_column_is_added_as_null(mock_bq_client_cls, mock_storage_client_cls, mock_gcs_blob, mock_storage_client, mock_bigquery_client):
    """
    Tests that a column defined in the schema but missing from the CSV is added as a NULL column.
    """
    # --- Arrange ---
    mock_storage_client_cls.return_value = mock_storage_client
    mock_bq_client_cls.return_value = mock_bigquery_client

    event = create_mock_event({"bucket": "test-bucket", "name": "test-file.csv"})
    
    csv_content = b"""\
"\xe6\x97\xa5\xe4\xbb\x98","\xe9\x87\x91\xe9\xa1\x8d"
"10/17/2025","100.00"
"""
    mock_gcs_blob.download_as_bytes.return_value = csv_content
    
    mock_bigquery_client.get_table.side_effect = NotFound("Table not found")
    
    # --- Act ---
    load_airbnb_csv(event, None)
    
    # --- Assert ---
    loaded_df = mock_bigquery_client.load_table_from_dataframe.call_args[0][0]
    assert 'pet_fee' in loaded_df.columns
    assert loaded_df['pet_fee'][0] is None

@patch('src.functions.storage.Client')
@patch('src.functions.bigquery.Client')
def test_airbnb_remitted_tax_column_is_mapped_and_merged(
    mock_bq_client_cls,
    mock_storage_client_cls,
    mock_gcs_blob,
    mock_storage_client,
    mock_bigquery_client
):
    """
    Tests that Airbnb's new English tax column is normalized and included in MERGE SQL.
    """
    mock_storage_client_cls.return_value = mock_storage_client
    mock_bq_client_cls.return_value = mock_bigquery_client

    event = create_mock_event({"bucket": "test-bucket", "name": "test-file.csv"})

    csv_content = b"""\
"\xe6\x97\xa5\xe4\xbb\x98","Airbnb remitted tax","\xe7\xb7\x8f\xe5\x8f\x8e\xe5\x85\xa5"
"03/12/2026","12.34","23527.00"
"""
    mock_gcs_blob.download_as_bytes.return_value = csv_content
    mock_bigquery_client.get_table.return_value = MagicMock()

    load_airbnb_csv(event, None)

    loaded_df = mock_bigquery_client.load_table_from_dataframe.call_args[0][0]
    assert 'airbnb_remitted_tax' in loaded_df.columns
    assert loaded_df['airbnb_remitted_tax'][0] == Decimal("12.34")

    load_job_config = mock_bigquery_client.load_table_from_dataframe.call_args[1]["job_config"]
    schema_names = [field.name for field in load_job_config.schema]
    assert "airbnb_remitted_tax" in schema_names

    merge_sql = mock_bigquery_client.query.call_args[0][0]
    assert "`airbnb_remitted_tax`" in merge_sql
    assert "`Airbnb remitted tax`" not in merge_sql

@patch('src.functions.storage.Client')
@patch('src.functions.bigquery.Client')
def test_unmapped_columns_emit_actionable_warning(
    mock_bq_client_cls,
    mock_storage_client_cls,
    mock_gcs_blob,
    mock_storage_client,
    mock_bigquery_client,
    caplog
):
    """
    Tests that unexpected Airbnb columns emit a warning with next-step guidance.
    """
    mock_storage_client_cls.return_value = mock_storage_client
    mock_bq_client_cls.return_value = mock_bigquery_client

    event = create_mock_event({"bucket": "test-bucket", "name": "test-file.csv"})

    csv_content = b"""\
"\xe6\x97\xa5\xe4\xbb\x98","Unexpected Airbnb Column","\xe9\x87\x91\xe9\xa1\x8d"
"03/12/2026","foo","100.00"
"""
    mock_gcs_blob.download_as_bytes.return_value = csv_content
    mock_bigquery_client.get_table.return_value = MagicMock()

    with caplog.at_level(logging.WARNING):
        load_airbnb_csv(event, None)

    assert "Detected unmapped Airbnb CSV columns" in caplog.text
    assert "Unexpected Airbnb Column" in caplog.text
    assert "add explicit mappings and schema fields" in caplog.text
    assert "recreate it or update its schema to match" in caplog.text
