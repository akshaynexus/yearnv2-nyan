import sys
from brownie import *


def main():
    original_stdout = sys.stdout  # Save a reference to the original standard output

    with open("flatstrat.sol", "w") as f:
        sys.stdout = f  # Change the standard output to the file we created.
        print(Strategy.get_verification_info()["flattened_source"])
        sys.stdout = original_stdout  # Reset the standard output to its original valueA
