import os
import glob
import re

def main():
    lib_dir = os.path.join(os.getcwd(), 'lib')
    all_files = glob.glob(os.path.join(lib_dir, '**', '*.dart'), recursive=True)
    
    file_contents = {}
    for f in all_files:
        with open(f, 'r', encoding='utf-8') as file:
            file_contents[f] = file.read()
            
    unused_files = []
    
    for target_file in all_files:
        if target_file.endswith('main.dart'):
            continue
            
        basename = os.path.basename(target_file)
        
        # Check if basename is mentioned in any other file
        is_used = False
        for f, content in file_contents.items():
            if f == target_file:
                continue
            if basename in content:
                is_used = True
                break
                
        if not is_used:
            unused_files.append(target_file)
            
    print("Potentially Unused Dart Files:")
    for f in unused_files:
        print(os.path.relpath(f, os.getcwd()))

if __name__ == '__main__':
    main()
