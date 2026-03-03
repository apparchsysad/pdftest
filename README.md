This repo contains: 
1. a powershell script to read a folder of PDF files from Google cloud storage, extract any text content, combine the resultant records into a json and, finall, save this as a file in the /public folder of a React project
2. a React component to display an input field to receive a keyword space, search the /public json for instances of these and display the results

The circumstances that led to the devlopment of this code are described at [Searching PDF files - GCSE and "local-code" options](https://dev.to/mjoycemilburn/searching-pdf-files-coding-a-goggle-custom-search-engine-gcse-component-in-react-36fk)