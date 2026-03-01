# This is the entrypoint for the Cloud Function.
# It imports the actual function logic from the 'src' directory.

from src.functions import load_airbnb_csv

__all__ = ["load_airbnb_csv"]
