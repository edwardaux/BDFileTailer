# BDFileTailer
At its simplest, this is a class that can be used to simply and easily read lines one at a time from a file.  However, it also offers the ability to tail a file (ie. wait for more data to be written to the file).

## Basic Example
An example of how to use the class is as follows:

<pre lang="objc">
BDFileTailer *tailer = [[BDFileTailer alloc] initWithURL:url];
NSString *line = [tailer readLine];
while (line != nil) {
	NSLog(@"Line:  %@", line);
	line = [self.tailer readLine];
}
</pre> 

It will continue to read lines from the file, until there are no more.  At this point, it will return a `nil`.  By default, the `NSString` objects returned will be encoded using the UTF8 encoding.

After each line, you can query the `tailer` object for one of two useful properties:

* `lastLineNumber` - The line number of the last-read line. Note that this is a 1-based index.
* `lastLineFileOffset` - The raw file offset of the start of the last-read line.  This is a 0-based index.

### Configuring Behaviour
There are several properties that can be set that will modify the way `BDFileTailer` works.

* `bufferSize` - To assist with performance, `BDFileTailer` uses an internal buffer to read data from the input file.  The default size if 4096, but it can be overridden using this property.
* `lineEndIndicator` - Allows you to define how *line-end* is recognized.  The following options are supported:
	* `BDFileTailerLineEndAuto` - Will match CR, or CRLF (this is the default)
	* `BDFileTailerLineEndOnlyCR` - A lone CR signifies line-end
	* `BDFileTailerLineEndOnlyLF` -  A lone LF signifies line-end
	* `BDFileTailerLineEndCRLF` - Needs both CR and LF for line-end
* `shouldStripLineEnds` - By default, the trailing line-end character(s) are faithfully returned as part of the returned line.  By setting this property to `YES`, the line-ends will be trimmed off.
* `encodings` - An array of `NSStringEncoding` enums that will be used to try and encode the raw data into a string.  For every line read, each encoding is attempted in succession, and the first that is able to successfully encode into an `NSString` will be used.

## Tailing a File
In addition to the properties defined above, there are two properties that can be used to enable tailing as can be seen in the example below:

<pre lang="objc">
BDFileTailer *tailer = [[BDFileTailer alloc] initWithURL:url];
tailer.shouldTail = YES;
tailer.tailFrequency = 1.0;  
NSString *line = [tailer readLine];
</pre>

When `shouldTail` is set to `YES`, calls to `readLine` or `readLineAsData` will block indefinitely until there is no more data in the file.  The `tailFrequency` property controls how often the file will be rechecked for more data (the default is every second).

To stop tailing, the `[BDFileTailer stopTailing]` method must be called on a secondary thread.  

**Note:** Do not tail on the main thread, otherwise the UI thread will be blocked while waiting for more input.  It is recommended to run the tail on a background thread using gcd, `NSTask`, or any of the other many background techniques.

## Following File Renames
There are many processes (such as Apache) that start writing to a particular file and once the file exceeds a certain size or date the file is closed, renamed, and a new file is renamed with the same name as the original.

If the `shouldFollowRename` property is set, `BDFileTailer` will read any remaining lines from the renamed file, and then open the new file and start reading lines from that file.