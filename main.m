#import <Foundation/Foundation.h>
#import <PDFKit/PDFKit.h>
#import <fcntl.h>
#import <unistd.h>

static BOOL IsHelpFlag(const char *arg) {
    return strcmp(arg, "-h") == 0 || strcmp(arg, "--help") == 0;
}

static BOOL IsVerboseFlag(const char *arg) {
    return strcmp(arg, "-v") == 0 || strcmp(arg, "--verbose") == 0;
}

static BOOL IsJobsFlag(const char *arg) {
    return strcmp(arg, "-j") == 0 || strcmp(arg, "--jobs") == 0;
}

static BOOL IsOverwriteFlag(const char *arg) {
    return strcmp(arg, "-o") == 0 || strcmp(arg, "--overwrite") == 0;
}

static BOOL IsDryRunFlag(const char *arg) { return strcmp(arg, "--dry-run") == 0; }

static BOOL IsPrefixFlag(const char *arg) {
    return strcmp(arg, "-p") == 0 || strcmp(arg, "--prefix") == 0;
}

static void PrintUsage(const char *program) {
    fprintf(stderr, "Native macOS PDF OCR Tool\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "This utility converts scanned, image-based PDFs into searchable documents\n");
    fprintf(stderr, "using Apple's native Live Text technology (Apple Vision Framework + PDFKit\n");
    fprintf(stderr, "on macOS 13.0+). It embeds an invisible OCR text layer without third-party\n");
    fprintf(stderr, "dependencies like Tesseract.\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "Usage:\n");
    fprintf(stderr, "  %s [options] <input.pdf> [more.pdf ...]\n", program);
    fprintf(stderr, "\n");
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -h, --help            Show this help and exit\n");
    fprintf(stderr, "  -v, --verbose         Print progress messages\n");
    fprintf(stderr, "  -o, --overwrite       Overwrite input files in place\n");
    fprintf(stderr, "  --dry-run             Print planned outputs without writing files\n");
    fprintf(stderr, "  -p, --prefix STR      Prefix for output files (default: OCR_)\n");
    fprintf(stderr, "  -j, --jobs N          Number of parallel jobs (default: 1)\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "Example:\n");
    fprintf(stderr, "  %s invoice.pdf\n", program);
    fprintf(stderr, "  %s --overwrite -j 4 **/*.pdf\n", program);
    fprintf(stderr, "\n");
    fprintf(stderr,
            "Outputs are written next to inputs with an OCR_ prefix unless --overwrite is set.\n");
}

static NSString *OutputPathForInput(NSString *inputPath, NSString *prefix) {
    NSString *directory = [inputPath stringByDeletingLastPathComponent];
    NSString *filename = [inputPath lastPathComponent];
    NSString *outputName = [prefix stringByAppendingString:filename];
    return [directory stringByAppendingPathComponent:outputName];
}

static void PrintProgress(int completed, int total) {
    if (total <= 0) {
        return;
    }
    const int barWidth = 30;
    int filled = (int)((long long)completed * barWidth / total);
    int percent = (int)((long long)completed * 100 / total);
    printf("\r[");
    for (int i = 0; i < barWidth; i++) {
        putchar(i < filled ? '#' : '-');
    }
    printf("] %3d%% (%d/%d)", percent, completed, total);
    fflush(stdout);
    if (completed == total) {
        printf("\n");
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            PrintUsage(argv[0]);
            return 1;
        }

        BOOL verbose = NO;
        BOOL showHelp = NO;
        BOOL overwrite = NO;
        BOOL dryRun = NO;
        NSString *prefix = @"OCR_";
        NSInteger jobs = 1;
        NSMutableArray<NSString *> *inputs = [NSMutableArray array];

        for (int i = 1; i < argc; i++) {
            if (IsHelpFlag(argv[i])) {
                showHelp = YES;
                continue;
            }
            if (IsVerboseFlag(argv[i])) {
                verbose = YES;
                continue;
            }
            if (IsOverwriteFlag(argv[i])) {
                overwrite = YES;
                continue;
            }
            if (IsDryRunFlag(argv[i])) {
                dryRun = YES;
                continue;
            }
            if (IsPrefixFlag(argv[i])) {
                if (i + 1 >= argc) {
                    fprintf(stderr, "Error: %s requires a prefix value.\n", argv[i]);
                    return 1;
                }
                prefix = [NSString stringWithUTF8String:argv[i + 1]];
                i++;
                continue;
            }
            if (IsJobsFlag(argv[i])) {
                if (i + 1 >= argc) {
                    fprintf(stderr, "Error: %s requires a number of jobs.\n", argv[i]);
                    return 1;
                }
                jobs = (NSInteger)strtol(argv[i + 1], NULL, 10);
                if (jobs < 1) {
                    fprintf(stderr, "Error: jobs must be >= 1.\n");
                    return 1;
                }
                i++;
                continue;
            }
            [inputs addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        if (showHelp) {
            PrintUsage(argv[0]);
            return 0;
        }

        if ([inputs count] == 0) {
            PrintUsage(argv[0]);
            return 1;
        }

        if (!verbose) {
            int devNull = open("/dev/null", O_WRONLY);
            if (devNull != -1) {
                dup2(devNull, STDERR_FILENO);
                close(devNull);
            }
        }

        CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();

        NSDictionary *options = @{PDFDocumentSaveTextFromOCROption : @YES};

        __block int failures = 0;
        __block int completed = 0;
        int total = (int)[inputs count];
        dispatch_queue_t workQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        dispatch_queue_t resultQueue =
            dispatch_queue_create("ocrmacpdf.results", DISPATCH_QUEUE_SERIAL);
        dispatch_group_t group = dispatch_group_create();
        dispatch_semaphore_t throttle = dispatch_semaphore_create(jobs);

        if (!verbose && !dryRun) {
            PrintProgress(0, total);
        }

        for (NSString *inputPath in inputs) {
            dispatch_semaphore_wait(throttle, DISPATCH_TIME_FOREVER);
            dispatch_group_async(group, workQueue, ^{
                @autoreleasepool {
                    NSString *outputPath =
                        overwrite ? inputPath : OutputPathForInput(inputPath, prefix);
                    NSString *inputPathCopy = [inputPath copy];
                    NSString *outputPathCopy = [outputPath copy];
                    const char *inputCString = [inputPathCopy UTF8String];
                    NSURL *inputURL = [NSURL fileURLWithPath:inputPath];
                    PDFDocument *pdfDoc = [[PDFDocument alloc] initWithURL:inputURL];

                    BOOL success = YES;

                    if (!pdfDoc) {
                        fprintf(stderr, "Error: Could not load PDF at %s\n", inputCString);
                        success = NO;
                    } else {
                        if (verbose) {
                            printf("Starting OCR: %s\n", inputCString);
                        }
                        if (!dryRun) {
                            success = [pdfDoc writeToFile:outputPath withOptions:options];
                        }
                        if (!success) {
                            fprintf(stderr, "Error: Failed to save OCR PDF for %s\n", inputCString);
                        }
                    }

                    dispatch_async(resultQueue, ^{
                        completed++;
                        if (!success) {
                            failures++;
                        }
                        if (verbose) {
                            int percent = (int)((long long)completed * 100 / total);
                            printf("%s: %s (%d/%d, %d%%)\n",
                                   success ? (dryRun ? "Would save" : "Saved") : "Failed",
                                   success ? [outputPathCopy UTF8String]
                                           : [inputPathCopy UTF8String],
                                   completed, total, percent);
                        } else if (dryRun && success) {
                            printf("Would save: %s\n", [outputPathCopy UTF8String]);
                        }
                        if (!verbose && !dryRun) {
                            PrintProgress(completed, total);
                        }
                    });
                    dispatch_semaphore_signal(throttle);
                }
            });
        }

        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        dispatch_sync(resultQueue, ^{
                      });

        if (verbose) {
            CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - startTime;
            printf("Total time: %.2f seconds\n", elapsed);
        }

        return failures == 0 ? 0 : 1;
    }
}
